import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/book.dart';
import 'app_exceptions.dart';
import 'isbn_validator.dart';

/// Könyv-metaadatok lekéréséért felelős szolgáltatás külső API-kból.
///
/// Keresési folyamat (maximális sebességre optimalizálva):
///
/// 1. fázis — Gyors angol / nemzetközi JSON API-k (elsőként futnak):
///   1. Google Books API (ISBN-13 előnyben részesítve, majd ISBN-10)
///   2. Open Library Books API (ISBN-13 és ISBN-10 együtt, egyetlen kérésben)
///   3. Open Library Search API (szélesebb nemzetközi / manga / képregény lefedettség)
///
/// 2. fázis — Lassú magyar HTML kereső tartalék (csak ha az 1. fázis nem adott találatot):
///   4. Moly.hu HTML keresés (kizárólag végső tartalékként, mivel a Moly.hu-nak nincs nyilvános API-ja)
class BookApiService {
  final Dio _dio;

  // Google Books API kulcs — `null` érték esetén a nyilvános kvótát használja
  static const String? _googleBooksApiKey = null;

  BookApiService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
              headers: {
                'User-Agent': 'FreeLib/1.0 (personal book library app)',
              },
            ));

  /// Könyv keresése ISBN alapján:
  /// 1) Először a gyors angol/nemzetközi JSON API-kban keres (Google Books, Open Library).
  /// 2) Csak akkor tér át a magyar Moly.hu keresésre, ha egyik angol API sem adott találatot.
  ///
  /// [NetworkException] kivételt dob, ha minden lekérdezés kapcsolódási hiba miatt hiúsul meg.
  Future<Book?> lookupByIsbn(String rawIsbn) async {
    final isbn = IsbnValidator.normalize(rawIsbn);
    if (isbn == null) return null;

    // A 13 jegyű ISBN előresorolása, majd utána a 10 jegyű változat
    final formats = _prioritizeIsbn13(IsbnValidator.getAllFormats(isbn));
    final tracker = _RequestHealthTracker();

    // ══════════════════════════════════════════════════════════════════
    // 1. FÁZIS: Angol / nemzetközi JSON API-k (gyors lekérdezés)
    // ══════════════════════════════════════════════════════════════════

    // 1.1 Google Books API
    for (final format in formats) {
      final googleBook = await _lookupGoogleBooks(format, tracker);
      if (googleBook != null) return _applyTranslation(googleBook);
      if (tracker.isOffline) break;
    }

    // 1.2 Open Library Direct ISBN API (egyetlen kérésben az összes ISBN formátum)
    if (!tracker.isOffline) {
      final openLibBook = await _lookupOpenLibraryBatch(formats, tracker);
      if (openLibBook != null) return _applyTranslation(openLibBook);
    }

    // 1.3 Open Library Search API (szélesebb angol/nemzetközi találatok)
    if (!tracker.isOffline) {
      final searchResult = await _searchOpenLibrary(formats.first, tracker);
      if (searchResult != null) return _applyTranslation(searchResult);
    }

    // ══════════════════════════════════════════════════════════════════
    // 2. FÁZIS: Magyar tartalék (Moly.hu — csak ha az angol API-kban nincs)
    // ══════════════════════════════════════════════════════════════════
    if (!tracker.isOffline) {
      final molyResult = await _lookupMoly(isbn, tracker);
      if (molyResult != null) return _applyTranslation(molyResult);
    }

    if (tracker.shouldThrowNetworkError) {
      throw const NetworkException();
    }

    return null;
  }

  /// Biztosítja, hogy a 13 jegyű ISBN-ek megelőzzék a 10 jegyűeket a gyorsabb találat érdekében.
  List<String> _prioritizeIsbn13(List<String> formats) {
    final sorted = List<String>.from(formats);
    sorted.sort((a, b) => b.length.compareTo(a.length));
    return sorted;
  }

  /// Könyvek online keresése cím, szerző vagy kulcsszó alapján.
  ///
  /// Először a Google Books API-t használja, szükség esetén az Open Library Search API-ra tér át.
  /// [NetworkException] kivételt dob, ha a keresés internetkapcsolat hiánya miatt meghiúsul.
  Future<List<Book>> searchBooksOnline(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    // Ha a felhasználó érvényes ISBN-t írt a keresőmezőbe, a gyors ISBN-lekérdezést futtatjuk
    final normalizedIsbn = IsbnValidator.normalize(trimmed);
    if (normalizedIsbn != null && IsbnValidator.isValid(normalizedIsbn)) {
      final exact = await lookupByIsbn(normalizedIsbn);
      if (exact != null) return [exact];
    }

    final tracker = _RequestHealthTracker();
    final results = <Book>[];
    final seenIsbns = <String>{};

    // 1. Google Books keresés (angol/nemzetközi API)
    try {
      final response = await _dio.get(
        'https://www.googleapis.com/books/v1/volumes',
        queryParameters: {
          'q': trimmed,
          'maxResults': 15,
          'printType': 'books',
          if (_googleBooksApiKey != null) 'key': _googleBooksApiKey,
        },
      );
      tracker.recordSuccess();

      final data = response.data;
      if (data is Map<String, dynamic>) {
        final items = data['items'] as List<dynamic>? ?? const [];
        for (final item in items) {
          if (item is! Map<String, dynamic>) continue;
          final book = _parseGoogleVolumeItem(item);
          if (book != null && seenIsbns.add(book.isbn)) {
            results.add(book);
          }
        }
      }
    } on DioException catch (e) {
      tracker.recordDioError(e);
    } catch (e) {
      debugPrint('Google Books keresési hiba: $e');
    }

    if (results.isNotEmpty) return results;

    // 2. Tartalék: Open Library Search API
    if (!tracker.isOffline) {
      try {
        final response = await _dio.get(
          'https://openlibrary.org/search.json',
          queryParameters: {
            'q': trimmed,
            'fields':
                'key,title,subtitle,author_name,publisher,publish_date,number_of_pages_median,subject,cover_i,isbn,ratings_average,ratings_count',
            'limit': 15,
          },
        );
        tracker.recordSuccess();

        final data = response.data;
        if (data is Map<String, dynamic>) {
          final docs = data['docs'] as List<dynamic>? ?? const [];
          for (final rawDoc in docs) {
            if (rawDoc is! Map<String, dynamic>) continue;
            final book = _parseOpenLibrarySearchDoc(rawDoc);
            if (book != null && seenIsbns.add(book.isbn)) {
              results.add(book);
            }
          }
        }
      } on DioException catch (e) {
        tracker.recordDioError(e);
      } catch (e) {
        debugPrint('Open Library keresési hiba: $e');
      }
    }

    if (results.isEmpty && tracker.shouldThrowNetworkError) {
      throw const NetworkException();
    }

    return results;
  }

  // ── Google Books API ──

  Future<Book?> _lookupGoogleBooks(
    String isbn,
    _RequestHealthTracker tracker,
  ) async {
    try {
      final response = await _dio.get(
        'https://www.googleapis.com/books/v1/volumes',
        queryParameters: {
          'q': 'isbn:$isbn',
          if (_googleBooksApiKey != null) 'key': _googleBooksApiKey,
        },
      );
      tracker.recordSuccess();

      final data = response.data;
      if (data is! Map<String, dynamic>) return null;
      final totalItems = (data['totalItems'] as num?)?.toInt() ?? 0;
      if (totalItems == 0) return null;

      final items = data['items'] as List<dynamic>?;
      if (items == null || items.isEmpty) return null;

      final firstItem = items[0];
      if (firstItem is! Map<String, dynamic>) return null;

      return _parseGoogleVolumeItem(firstItem, explicitIsbn: isbn);
    } on DioException catch (e) {
      tracker.recordDioError(e);
      return null;
    } catch (e) {
      debugPrint('Google Books lekérdezési hiba: $e');
      return null;
    }
  }

  Book? _parseGoogleVolumeItem(
    Map<String, dynamic> item, {
    String? explicitIsbn,
  }) {
    final volumeInfo = item['volumeInfo'] as Map<String, dynamic>?;
    if (volumeInfo == null) return null;

    // ISBN-13 (előnyben részesített) vagy ISBN-10 kinyerése
    String? resolvedIsbn = explicitIsbn;
    if (resolvedIsbn == null) {
      final identifiers = volumeInfo['industryIdentifiers'] as List<dynamic>?;
      String? isbn13;
      String? isbn10;
      if (identifiers != null) {
        for (final idObj in identifiers) {
          if (idObj is! Map<String, dynamic>) continue;
          final type = idObj['type'] as String?;
          final identifier = idObj['identifier'] as String?;
          if (identifier == null) continue;
          if (type == 'ISBN_13') {
            isbn13 = IsbnValidator.normalize(identifier) ?? identifier;
          } else if (type == 'ISBN_10') {
            isbn10 = IsbnValidator.normalize(identifier) ?? identifier;
          }
        }
      }
      resolvedIsbn = isbn13 ?? isbn10;
    }

    final volumeId = item['id'] as String?;
    resolvedIsbn ??=
        'LOCAL-GB-${volumeId ?? DateTime.now().millisecondsSinceEpoch}';

    // Borítókép URL kinyerése (nagyobb felbontás előnyben részesítve)
    String? coverUrl;
    final imageLinks = volumeInfo['imageLinks'] as Map<String, dynamic>?;
    if (imageLinks != null) {
      coverUrl = (imageLinks['extraLarge'] as String?) ??
          (imageLinks['large'] as String?) ??
          (imageLinks['medium'] as String?) ??
          (imageLinks['thumbnail'] as String?) ??
          (imageLinks['smallThumbnail'] as String?);
      coverUrl = coverUrl?.replaceAll('http://', 'https://');
    }

    if (coverUrl == null && !resolvedIsbn.startsWith('LOCAL-')) {
      coverUrl = _buildOpenLibraryCoverUrl(resolvedIsbn);
    }

    final authors = volumeInfo['authors'] as List<dynamic>?;
    final categories = volumeInfo['categories'] as List<dynamic>?;

    final avgRating = (volumeInfo['averageRating'] as num?)?.toDouble();
    final ratingsCount = (volumeInfo['ratingsCount'] as num?)?.toInt();

    return Book(
      isbn: resolvedIsbn,
      title: volumeInfo['title'] as String? ?? 'Ismeretlen cím',
      subtitle: volumeInfo['subtitle'] as String?,
      authors: authors?.map((a) => a.toString()).join(', '),
      publisher: volumeInfo['publisher'] as String?,
      publishedDate: volumeInfo['publishedDate'] as String?,
      description: volumeInfo['description'] as String?,
      pageCount: (volumeInfo['pageCount'] as num?)?.toInt(),
      categories: categories?.map((c) => c.toString()).join(', '),
      coverUrl: coverUrl,
      dateAdded: DateTime.now(),
      externalRating: avgRating,
      externalRatingCount: ratingsCount,
      externalRatingSource: avgRating != null ? 'Google Books' : null,
    );
  }

  // ── Open Library Books API (kötegelt ISBN-13 + ISBN-10 lekérdezés 1 kérésben) ──

  Future<Book?> _lookupOpenLibraryBatch(
    List<String> formats,
    _RequestHealthTracker tracker,
  ) async {
    if (formats.isEmpty) return null;
    try {
      final bibkeys = formats.map((f) => 'ISBN:$f').join(',');
      final response = await _dio.get(
        'https://openlibrary.org/api/books',
        queryParameters: {
          'bibkeys': bibkeys,
          'jscmd': 'details',
          'format': 'json',
        },
      );
      tracker.recordSuccess();

      final data = response.data;
      if (data is! Map<String, dynamic> || data.isEmpty) return null;

      for (final isbn in formats) {
        final key = 'ISBN:$isbn';
        if (!data.containsKey(key)) continue;
        final entry = data[key];
        if (entry is! Map<String, dynamic>) continue;
        final details = entry['details'] as Map<String, dynamic>?;
        if (details == null) continue;

        return await _parseOpenLibraryDetails(isbn, entry, details);
      }
      return null;
    } on DioException catch (e) {
      tracker.recordDioError(e);
      return null;
    } catch (e) {
      debugPrint('Open Library kötegelt lekérdezési hiba: $e');
      return null;
    }
  }

  // ── Open Library Search API (szélesebb lefedettség mangákhoz, képregényekhez stb.) ──

  Future<Book?> _searchOpenLibrary(
    String isbn,
    _RequestHealthTracker tracker,
  ) async {
    try {
      final response = await _dio.get(
        'https://openlibrary.org/search.json',
        queryParameters: {
          'isbn': isbn,
          'fields':
              'key,title,subtitle,author_name,publisher,publish_date,number_of_pages_median,subject,cover_i,isbn,ratings_average,ratings_count',
          'limit': 1,
        },
      );
      tracker.recordSuccess();

      final data = response.data;
      if (data is! Map<String, dynamic>) return null;
      final numFound = (data['numFound'] as num?)?.toInt() ?? 0;
      if (numFound == 0) return null;

      final docs = data['docs'] as List<dynamic>?;
      if (docs == null || docs.isEmpty) return null;

      final doc = docs[0];
      if (doc is! Map<String, dynamic>) return null;

      return _parseOpenLibrarySearchDoc(doc, explicitIsbn: isbn);
    } on DioException catch (e) {
      tracker.recordDioError(e);
      return null;
    } catch (e) {
      debugPrint('Open Library ISBN keresési hiba: $e');
      return null;
    }
  }

  // ── Moly.hu (magyar adatbázis tartalék HTML feldolgozó — VÉGSŐ tartalék) ──

  Future<Book?> _lookupMoly(
    String isbn,
    _RequestHealthTracker tracker,
  ) async {
    try {
      final response = await _dio.get(
        'https://moly.hu/kereses',
        queryParameters: {'q': isbn},
        options: Options(
          followRedirects: true,
          sendTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
          validateStatus: (status) => (status ?? 500) < 500,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
            'Accept-Language': 'hu-HU,hu;q=0.9,en-US;q=0.8,en;q=0.7',
          },
        ),
      );
      tracker.recordSuccess();

      final rawData = response.data;
      if (rawData is! String) return null;
      var html = rawData;

      if (html.contains('Nincs találat') || html.contains('Nem található')) {
        return null;
      }

      // Cím és szerző kinyerése a <title> elemből
      // Formátum közvetlen könyvoldalon: "Szerző: Cím · Moly" vagy "Cím · Moly"
      var titleMatch =
          RegExp(r'<title>(.*?) · Moly<\/title>').firstMatch(html);
      if (titleMatch == null) return null;

      var pageTitle = _decodeHtmlEntities(titleMatch.group(1) ?? '').trim();

      // Ha a Moly találati listát ("Keresés") adott vissza átirányítás helyett,
      // követjük az első /konyvek/... hivatkozást, ha van ilyen.
      if (pageTitle.isEmpty || pageTitle.startsWith('Keresés')) {
        final bookLinkMatch =
            RegExp(r'href="(\/konyvek\/[^"#?]+)"').firstMatch(html);
        if (bookLinkMatch == null) return null;

        final bookPath = bookLinkMatch.group(1)!;
        final bookPageResp = await _dio.get(
          'https://moly.hu$bookPath',
          options: Options(
            sendTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
            validateStatus: (status) => (status ?? 500) < 500,
          ),
        );
        if (bookPageResp.data is! String) return null;
        html = bookPageResp.data as String;
        titleMatch = RegExp(r'<title>(.*?) · Moly<\/title>').firstMatch(html);
        if (titleMatch == null) return null;
        pageTitle = _decodeHtmlEntities(titleMatch.group(1) ?? '').trim();
        if (pageTitle.isEmpty || pageTitle.startsWith('Keresés')) return null;
      }

      String author = '';
      String title = pageTitle;

      if (pageTitle.contains(': ')) {
        final parts = pageTitle.split(': ');
        author = parts.first.trim();
        title = parts.sublist(1).join(': ').trim();
      }

      // Borítókép URL kinyerése
      final coverMatch = RegExp(
              r'(https:\/\/moly\.hu\/system\/covers\/big\/.*?\.jpg)')
          .firstMatch(html);
      final String? coverUrl = coverMatch?.group(1);

      // Közösségi értékelés kinyerése, ha elérhető (a Moly százalékot használ, pl. 93%)
      double? externalRating;
      final ratingMatch = RegExp(r'(\d+)%<\/span>').firstMatch(html);
      if (ratingMatch != null) {
        final percentage = double.tryParse(ratingMatch.group(1) ?? '0');
        if (percentage != null && percentage > 0) {
          externalRating = (percentage / 20).clamp(0.0, 5.0);
        }
      }

      return Book(
        isbn: isbn,
        title: title.isEmpty ? 'Ismeretlen cím' : title,
        authors: author.isEmpty ? null : author,
        coverUrl: coverUrl,
        dateAdded: DateTime.now(),
        externalRating: externalRating,
        externalRatingSource: externalRating != null ? 'Moly.hu' : null,
      );
    } on DioException catch (e) {
      tracker.recordDioError(e);
      return null;
    } catch (e) {
      debugPrint('Moly lekérdezési hiba: $e');
      return null;
    }
  }

  String _decodeHtmlEntities(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#039;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&ndash;', '–')
        .replaceAll('&mdash;', '—')
        .replaceAll('&nbsp;', ' ');
  }

  Book? _parseOpenLibrarySearchDoc(
    Map<String, dynamic> doc, {
    String? explicitIsbn,
  }) {
    String? resolvedIsbn = explicitIsbn;
    if (resolvedIsbn == null) {
      final isbns = doc['isbn'] as List<dynamic>?;
      if (isbns != null && isbns.isNotEmpty) {
        for (final candidate in isbns) {
          final norm = IsbnValidator.normalize(candidate.toString());
          if (norm != null && norm.length == 13) {
            resolvedIsbn = norm;
            break;
          }
          resolvedIsbn ??= norm;
        }
      }
    }
    final key = (doc['key'] as String?)?.replaceAll('/works/', '') ??
        '${DateTime.now().millisecondsSinceEpoch}';
    resolvedIsbn ??= 'LOCAL-OL-$key';

    final coverId = (doc['cover_i'] as num?)?.toInt();
    String? coverUrl;
    if (coverId != null) {
      coverUrl = 'https://covers.openlibrary.org/b/id/$coverId-L.jpg';
    } else if (!resolvedIsbn.startsWith('LOCAL-')) {
      coverUrl = _buildOpenLibraryCoverUrl(resolvedIsbn);
    }

    final authorNames = doc['author_name'] as List<dynamic>?;
    final authors = authorNames?.map((a) => a.toString()).join(', ');

    final publishers = doc['publisher'] as List<dynamic>?;
    final publisher = publishers != null && publishers.isNotEmpty
        ? publishers.first.toString()
        : null;

    final subjects = doc['subject'] as List<dynamic>?;
    final categories = subjects?.take(5).map((s) => s.toString()).join(', ');

    final avgRating = (doc['ratings_average'] as num?)?.toDouble();
    final ratingsCount = (doc['ratings_count'] as num?)?.toInt();

    final publishDates = doc['publish_date'] as List<dynamic>?;

    return Book(
      isbn: resolvedIsbn,
      title: doc['title'] as String? ?? 'Ismeretlen cím',
      subtitle: doc['subtitle'] as String?,
      authors: authors,
      publisher: publisher,
      publishedDate: publishDates != null && publishDates.isNotEmpty
          ? publishDates.first.toString()
          : null,
      description: null,
      pageCount: (doc['number_of_pages_median'] as num?)?.toInt(),
      categories: categories,
      coverUrl: coverUrl,
      dateAdded: DateTime.now(),
      externalRating: avgRating,
      externalRatingCount: ratingsCount,
      externalRatingSource:
          avgRating != null && avgRating > 0 ? 'Open Library' : null,
    );
  }

  // ── Közös Open Library adatfeldolgozás ──

  Future<Book?> _parseOpenLibraryDetails(
    String isbn,
    Map<String, dynamic> entry,
    Map<String, dynamic> details,
  ) async {
    final authorsList = details['authors'] as List<dynamic>?;
    final authors = authorsList
        ?.map((a) {
          if (a is Map<String, dynamic>) return a['name'] as String?;
          if (a is String) return a;
          return null;
        })
        .whereType<String>()
        .join(', ');

    final publishers = details['publishers'] as List<dynamic>?;
    String? publisher;
    if (publishers != null && publishers.isNotEmpty) {
      final first = publishers.first;
      if (first is String) {
        publisher = first;
      } else if (first is Map<String, dynamic>) {
        publisher = first['name'] as String?;
      }
    }

    String? coverUrl = entry['thumbnail_url'] as String?;
    if (coverUrl != null) {
      coverUrl = coverUrl.replaceAll('-S.jpg', '-L.jpg');
    }
    coverUrl ??= _buildOpenLibraryCoverUrl(isbn);

    final pageCount = (details['number_of_pages'] as num?)?.toInt();

    String? description;
    final rawDesc = details['description'];
    if (rawDesc is String) {
      description = rawDesc;
    } else if (rawDesc is Map<String, dynamic>) {
      description = rawDesc['value'] as String?;
    }

    final subjects = details['subjects'] as List<dynamic>?;
    final categories = subjects
        ?.take(5)
        .map((s) {
          if (s is Map<String, dynamic>) return s['name'] as String?;
          if (s is String) return s;
          return null;
        })
        .whereType<String>()
        .join(', ');

    double? externalRating;
    int? externalRatingCount;
    String? externalRatingSource;

    final worksKey = _extractWorksKey(details);
    if (worksKey != null) {
      final ratings = await _fetchOpenLibraryRatings(worksKey);
      if (ratings != null) {
        externalRating = ratings.$1;
        externalRatingCount = ratings.$2;
        externalRatingSource = 'Open Library';
      }
    }

    return Book(
      isbn: isbn,
      title: details['title'] as String? ?? 'Ismeretlen cím',
      subtitle: details['subtitle'] as String?,
      authors: authors,
      publisher: publisher,
      publishedDate: details['publish_date'] as String?,
      description: description,
      pageCount: pageCount,
      categories: categories,
      coverUrl: coverUrl,
      dateAdded: DateTime.now(),
      externalRating: externalRating,
      externalRatingCount: externalRatingCount,
      externalRatingSource: externalRatingSource,
    );
  }

  String? _extractWorksKey(Map<String, dynamic> details) {
    try {
      final works = details['works'] as List<dynamic>?;
      if (works == null || works.isEmpty) return null;
      final firstWork = works.first as Map<String, dynamic>;
      final key = firstWork['key'] as String?;
      return key;
    } catch (_) {
      return null;
    }
  }

  /// Közösségi értékelések lekérése az Open Library értékelési API-jából (rövid, 2 mp-es időkorláttal).
  Future<(double, int)?> _fetchOpenLibraryRatings(String worksKey) async {
    try {
      final response = await _dio.get(
        'https://openlibrary.org$worksKey/ratings.json',
        options: Options(
          sendTimeout: const Duration(seconds: 2),
          receiveTimeout: const Duration(seconds: 2),
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final summary = data['summary'] as Map<String, dynamic>?;
      if (summary == null) return null;

      final average = (summary['average'] as num?)?.toDouble();
      final count = (summary['count'] as num?)?.toInt() ?? 0;

      if (average == null || average <= 0 || count == 0) return null;
      return (average, count);
    } catch (_) {
      return null;
    }
  }

  String _buildOpenLibraryCoverUrl(String isbn) {
    return 'https://covers.openlibrary.org/b/isbn/$isbn-L.jpg';
  }

  Future<bool> isCoverAvailable(String url) async {
    try {
      final response = await _dio.head(url);
      final contentLength =
          int.tryParse(response.headers.value('content-length') ?? '0') ?? 0;
      return contentLength > 1000;
    } catch (_) {
      return false;
    }
  }

  // ── Fordítás és latin betűs átírás (Romanizáció) ──

  Future<Book> _applyTranslation(Book book) async {
    String? originalTitle;
    String? romajiTitle;
    String newTitle = book.title;

    String? originalAuthor;
    String? newAuthor = book.authors;

    if (_isJapanese(book.title)) {
      originalTitle = book.title;
      final officialTitle = await _fetchOfficialTitle(book.title);
      if (officialTitle != null) {
        newTitle = officialTitle.toTitleCase();
        final trans = await _translateJapaneseText(book.title);
        if (trans != null) romajiTitle = trans.$2?.toTitleCase();
      } else {
        final trans = await _translateJapaneseText(book.title);
        if (trans != null) {
          if (trans.$1 != null) {
            newTitle = trans.$1!.toTitleCase();
            romajiTitle = trans.$2?.toTitleCase();
          } else {
            newTitle = (trans.$2 ?? book.title).toTitleCase();
          }
        }
      }
    }

    if (book.authors != null && _isJapanese(book.authors!)) {
      originalAuthor = book.authors;
      final officialAuthor = await _fetchOfficialAuthorName(book.authors!);
      if (officialAuthor != null) {
        newAuthor = officialAuthor.toTitleCase();
      } else {
        final trans = await _translateJapaneseText(book.authors!);
        if (trans != null) {
          newAuthor = (trans.$2 ?? trans.$1 ?? book.authors!).toTitleCase();
        }
      }
    }

    if (originalTitle != null || originalAuthor != null) {
      return book.copyWith(
        title: newTitle,
        authors: newAuthor,
        originalTitle: originalTitle,
        romajiTitle: romajiTitle,
        originalAuthor: originalAuthor,
      );
    }
    return book;
  }

  bool _isJapanese(String text) {
    return RegExp(
            r'[\u3000-\u303f\u3040-\u309f\u30a0-\u30ff\uff00-\uff9f\u4e00-\u9faf]')
        .hasMatch(text);
  }

  Future<(String?, String?)?> _translateJapaneseText(String text) async {
    try {
      final response = await _dio.get(
        'https://translate.googleapis.com/translate_a/single',
        queryParameters: {
          'client': 'gtx',
          'sl': 'ja',
          'tl': 'en',
          'dt': ['t', 'rm'],
          'q': text,
        },
      );

      final data = response.data as List<dynamic>?;
      if (data == null || data.isEmpty) return null;

      final sections = data[0] as List<dynamic>?;
      if (sections == null || sections.isEmpty) return null;

      String? englishText;
      String? romajiText;

      final firstSection = sections.first as List<dynamic>?;
      if (firstSection != null && firstSection.isNotEmpty) {
        englishText = firstSection[0] as String?;
      }

      final lastSection = sections.last as List<dynamic>?;
      if (lastSection != null && lastSection.length > 3) {
        romajiText = lastSection[3] as String?;
      }

      return (englishText, romajiText);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetchOfficialAuthorName(String japaneseName) async {
    try {
      final response = await _dio.get(
        'https://openlibrary.org/search/authors.json',
        queryParameters: {'q': japaneseName},
      );
      final data = response.data;
      if (data['docs'] == null || (data['docs'] as List).isEmpty) return null;

      final doc = data['docs'][0];
      final alternates = doc['alternate_names'] as List<dynamic>?;
      if (alternates == null) return null;

      for (final alt in alternates) {
        final name = alt.toString();
        if (!_isJapanese(name) && RegExp(r'^[a-zA-Z\s\.\-]+$').hasMatch(name)) {
          return name;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetchOfficialTitle(String japaneseTitle) async {
    try {
      final response = await _dio.get(
        'https://openlibrary.org/search.json',
        queryParameters: {'title': japaneseTitle},
      );
      final data = response.data;
      if (data['docs'] == null || (data['docs'] as List).isEmpty) return null;

      final doc = data['docs'][0];

      final alternates = doc['alternative_title'] as List<dynamic>?;
      if (alternates != null) {
        for (final alt in alternates) {
          final title = alt.toString();
          if (!_isJapanese(title) &&
              RegExp(r'^[a-zA-Z0-9\s\.\-\:\,\!\?]+$').hasMatch(title)) {
            return title;
          }
        }
      }

      final mainTitle = doc['title']?.toString();
      if (mainTitle != null &&
          !_isJapanese(mainTitle) &&
          RegExp(r'^[a-zA-Z0-9\s\.\-\:\,\!\?]+$').hasMatch(mainTitle)) {
        return mainTitle;
      }

      return null;
    } catch (_) {
      return null;
    }
  }
}

class _RequestHealthTracker {
  bool hadSuccessResponse = false;
  bool hadNetworkFailure = false;
  bool isOffline = false;

  void recordSuccess() {
    hadSuccessResponse = true;
    isOffline = false;
  }

  void recordDioError(DioException e) {
    if (e.type == DioExceptionType.connectionError) {
      hadNetworkFailure = true;
      isOffline = true;
    } else if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      hadNetworkFailure = true;
    }
  }

  bool get shouldThrowNetworkError => !hadSuccessResponse && hadNetworkFailure;
}

extension StringCasingExtension on String {
  String toTitleCase() {
    if (trim().isEmpty) return this;
    final exceptions = {
      'a',
      'an',
      'the',
      'and',
      'but',
      'or',
      'for',
      'nor',
      'on',
      'at',
      'to',
      'from',
      'by',
      'of',
      'in'
    };

    final words = split(' ');
    return words
        .asMap()
        .map((index, word) {
          if (word.isEmpty) return MapEntry(index, '');
          final lowerWord = word.toLowerCase();
          if (index == 0 ||
              index == words.length - 1 ||
              !exceptions.contains(lowerWord)) {
            return MapEntry(
                index, word[0].toUpperCase() + lowerWord.substring(1));
          }
          return MapEntry(index, lowerWord);
        })
        .values
        .join(' ');
  }
}

import 'package:dio/dio.dart';
import '../models/book.dart';
import 'isbn_validator.dart';

/// Service for fetching book metadata from external APIs.
///
/// Covers books, manga, comics, graphic novels, light novels, and
/// international editions by using multiple databases and ISBN formats.
///
/// Lookup strategy (each tried in order until a result is found):
/// 1. Google Books API — by ISBN-13 and ISBN-10
/// 2. Open Library Books API — direct ISBN lookup
/// 3. Open Library Search API — broader search (catches manga, comics, etc.)
/// 4. Open Library Covers API — direct URL construction for covers
class BookApiService {
  final Dio _dio;

  // Google Books API key — set to null to skip Google Books
  // Get one free at: https://console.cloud.google.com → Books API
  static const String? _googleBooksApiKey = null;

  BookApiService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: {
                'User-Agent': 'FreeLib/1.0 (personal book library app)',
              },
            ));

  /// Look up a book by ISBN. Tries all available databases and ISBN formats.
  /// Returns a partially-filled Book object, or null.
  ///
  /// Supports: books, manga, comics, graphic novels, light novels,
  /// translated editions, and any publication with a valid ISBN/EAN-13 barcode.
  Future<Book?> lookupByIsbn(String rawIsbn) async {
    final isbn = IsbnValidator.normalize(rawIsbn);
    if (isbn == null) return null;

    // Get all ISBN format variants (ISBN-10 + ISBN-13) for broader coverage
    final formats = IsbnValidator.getAllFormats(isbn);

    // ── Strategy 1: Google Books (best metadata + ratings) ──
    for (final format in formats) {
      final result = await _lookupGoogleBooks(format);
      if (result != null) return _applyTranslation(result);
    }

    // ── Strategy 2: Open Library direct ISBN lookup ──
    for (final format in formats) {
      final result = await _lookupOpenLibrary(format);
      if (result != null) return _applyTranslation(result);
    }

    // ── Strategy 3: Open Library Search API (broadest coverage) ──
    // Catches manga, comics, international editions that direct lookup misses
    final searchResult = await _searchOpenLibrary(isbn);
    if (searchResult != null) return _applyTranslation(searchResult);

    // ── Strategy 4: Moly.hu Scraper (for Hungarian/European editions) ──
    final molyResult = await _lookupMoly(isbn);
    if (molyResult != null) return _applyTranslation(molyResult);

    return null;
  }

  // ── Google Books API ──

  Future<Book?> _lookupGoogleBooks(String isbn) async {
    try {
      final response = await _dio.get(
        'https://www.googleapis.com/books/v1/volumes',
        queryParameters: {
          'q': 'isbn:$isbn',
          if (_googleBooksApiKey != null) 'key': _googleBooksApiKey,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final totalItems = data['totalItems'] as int? ?? 0;
      if (totalItems == 0) return null;

      final items = data['items'] as List<dynamic>;
      if (items.isEmpty) return null;

      final volumeInfo = items[0]['volumeInfo'] as Map<String, dynamic>;

      // Extract cover URL (prefer larger image)
      String? coverUrl;
      final imageLinks = volumeInfo['imageLinks'] as Map<String, dynamic>?;
      if (imageLinks != null) {
        // Prefer larger sizes: extraLarge > large > medium > thumbnail > smallThumbnail
        coverUrl = (imageLinks['extraLarge'] as String?) ??
            (imageLinks['large'] as String?) ??
            (imageLinks['medium'] as String?) ??
            (imageLinks['thumbnail'] as String?) ??
            (imageLinks['smallThumbnail'] as String?);
        coverUrl = coverUrl?.replaceAll('http://', 'https://');
      }

      // If no Google cover, use Open Library cover
      coverUrl ??= _buildOpenLibraryCoverUrl(isbn);

      final authors = volumeInfo['authors'] as List<dynamic>?;
      final categories = volumeInfo['categories'] as List<dynamic>?;

      // Extract community rating from Google Books
      final avgRating = (volumeInfo['averageRating'] as num?)?.toDouble();
      final ratingsCount = volumeInfo['ratingsCount'] as int?;

      return Book(
        isbn: isbn,
        title: volumeInfo['title'] as String? ?? 'Unknown Title',
        subtitle: volumeInfo['subtitle'] as String?,
        authors: authors?.join(', '),
        publisher: volumeInfo['publisher'] as String?,
        publishedDate: volumeInfo['publishedDate'] as String?,
        description: volumeInfo['description'] as String?,
        pageCount: volumeInfo['pageCount'] as int?,
        categories: categories?.join(', '),
        coverUrl: coverUrl,
        dateAdded: DateTime.now(),
        externalRating: avgRating,
        externalRatingCount: ratingsCount,
        externalRatingSource: avgRating != null ? 'Google Books' : null,
      );
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Moly.hu (Hungarian database scraper) ──

  Future<Book?> _lookupMoly(String isbn) async {
    try {
      final response = await _dio.get(
        'https://moly.hu/kereses',
        queryParameters: {'q': isbn},
        options: Options(
          followRedirects: true,
          validateStatus: (status) => status! < 500,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
            'Accept-Language': 'hu-HU,hu;q=0.9,en-US;q=0.8,en;q=0.7',
          },
        ),
      );

      final html = response.data as String;
      if (html.contains('Nincs találat') || html.contains('Nem található')) {
        return null;
      }

      // Parse title and author from <title> tag
      // Format usually: "Author: Title · Moly" or "Title · Moly"
      final titleMatch = RegExp(r'<title>(.*?) · Moly<\/title>').firstMatch(html);
      if (titleMatch == null) return null;

      final pageTitle = titleMatch.group(1) ?? '';
      String author = '';
      String title = pageTitle;

      if (pageTitle.contains(': ')) {
        final parts = pageTitle.split(': ');
        author = parts.first.trim();
        title = parts.sublist(1).join(': ').trim();
      }

      // Parse cover URL
      // Look for a link to the big cover image or an img tag
      final coverMatch = RegExp(r'(https:\/\/moly\.hu\/system\/covers\/big\/.*?\.jpg)').firstMatch(html);
      String? coverUrl = coverMatch?.group(1);

      // Parse community rating if available
      // e.g., <span class="rating">89</span> or similar... Moly uses percentages, e.g. 93%
      double? externalRating;
      final ratingMatch = RegExp(r'(\d+)%<\/span>').firstMatch(html);
      if (ratingMatch != null) {
        final percentage = double.tryParse(ratingMatch.group(1) ?? '0');
        if (percentage != null && percentage > 0) {
          // Convert percentage (0-100) to 5-star scale
          externalRating = (percentage / 20).clamp(0.0, 5.0);
        }
      }

      return Book(
        isbn: isbn,
        title: title.isEmpty ? 'Unknown Title' : title,
        authors: author.isEmpty ? null : author,
        coverUrl: coverUrl,
        dateAdded: DateTime.now(),
        externalRating: externalRating,
        externalRatingSource: externalRating != null ? 'Moly.hu' : null,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Open Library Books API (direct ISBN lookup) ──

  Future<Book?> _lookupOpenLibrary(String isbn) async {
    try {
      final response = await _dio.get(
        'https://openlibrary.org/api/books',
        queryParameters: {
          'bibkeys': 'ISBN:$isbn',
          'jscmd': 'details',
          'format': 'json',
        },
      );

      final data = response.data as Map<String, dynamic>;
      final key = 'ISBN:$isbn';

      if (!data.containsKey(key)) return null;

      final entry = data[key] as Map<String, dynamic>;
      final details = entry['details'] as Map<String, dynamic>?;
      if (details == null) return null;

      return await _parseOpenLibraryDetails(isbn, entry, details);
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Open Library Search API (broader coverage for manga, comics, etc.) ──

  Future<Book?> _searchOpenLibrary(String isbn) async {
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

      final data = response.data as Map<String, dynamic>;
      final numFound = data['numFound'] as int? ?? 0;
      if (numFound == 0) return null;

      final docs = data['docs'] as List<dynamic>;
      if (docs.isEmpty) return null;

      final doc = docs[0] as Map<String, dynamic>;

      // Build cover URL from cover ID
      final coverId = doc['cover_i'] as int?;
      String? coverUrl;
      if (coverId != null) {
        coverUrl = 'https://covers.openlibrary.org/b/id/$coverId-L.jpg';
      }
      coverUrl ??= _buildOpenLibraryCoverUrl(isbn);

      // Authors
      final authorNames = doc['author_name'] as List<dynamic>?;
      final authors = authorNames?.cast<String>().join(', ');

      // Publisher
      final publishers = doc['publisher'] as List<dynamic>?;
      final publisher =
          publishers != null && publishers.isNotEmpty ? publishers.first as String : null;

      // Categories / Subjects
      final subjects = doc['subject'] as List<dynamic>?;
      final categories =
          subjects?.take(5).cast<String>().join(', ');

      // Community rating from Open Library search
      final avgRating = (doc['ratings_average'] as num?)?.toDouble();
      final ratingsCount = doc['ratings_count'] as int?;

      return Book(
        isbn: isbn,
        title: doc['title'] as String? ?? 'Unknown Title',
        subtitle: doc['subtitle'] as String?,
        authors: authors,
        publisher: publisher,
        publishedDate: (doc['publish_date'] as List<dynamic>?)?.firstOrNull as String?,
        description: null,
        pageCount: doc['number_of_pages_median'] as int?,
        categories: categories,
        coverUrl: coverUrl,
        dateAdded: DateTime.now(),
        externalRating: avgRating,
        externalRatingCount: ratingsCount,
        externalRatingSource:
            avgRating != null && avgRating > 0 ? 'Open Library' : null,
      );
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Shared Open Library parsing ──

  Future<Book?> _parseOpenLibraryDetails(
    String isbn,
    Map<String, dynamic> entry,
    Map<String, dynamic> details,
  ) async {
    // Extract authors
    final authorsList = details['authors'] as List<dynamic>?;
    final authors = authorsList
        ?.map((a) => (a as Map<String, dynamic>)['name'] as String?)
        .whereType<String>()
        .join(', ');

    // Extract publishers (may be strings or objects with 'name' key)
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

    // Cover URL — try thumbnail from response, otherwise construct directly
    String? coverUrl = entry['thumbnail_url'] as String?;
    if (coverUrl != null) {
      coverUrl = coverUrl.replaceAll('-S.jpg', '-L.jpg');
    }
    coverUrl ??= _buildOpenLibraryCoverUrl(isbn);

    // Page count
    final pageCount = details['number_of_pages'] as int?;

    // Subjects as categories
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

    // Try to fetch Open Library community ratings via the works key
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
      title: details['title'] as String? ?? 'Unknown Title',
      subtitle: details['subtitle'] as String?,
      authors: authors,
      publisher: publisher,
      publishedDate: details['publish_date'] as String?,
      description: null,
      pageCount: pageCount,
      categories: categories,
      coverUrl: coverUrl,
      dateAdded: DateTime.now(),
      externalRating: externalRating,
      externalRatingCount: externalRatingCount,
      externalRatingSource: externalRatingSource,
    );
  }

  /// Extract the Open Library works key from book details.
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

  /// Fetch community ratings from Open Library's ratings API.
  Future<(double, int)?> _fetchOpenLibraryRatings(String worksKey) async {
    try {
      final response = await _dio.get(
        'https://openlibrary.org$worksKey/ratings.json',
      );

      final data = response.data as Map<String, dynamic>;
      final summary = data['summary'] as Map<String, dynamic>?;
      if (summary == null) return null;

      final average = (summary['average'] as num?)?.toDouble();
      final count = summary['count'] as int? ?? 0;

      if (average == null || average <= 0 || count == 0) return null;
      return (average, count);
    } catch (_) {
      return null;
    }
  }

  /// Build a direct Open Library cover URL from ISBN.
  String _buildOpenLibraryCoverUrl(String isbn) {
    return 'https://covers.openlibrary.org/b/isbn/$isbn-L.jpg';
  }

  /// Check if a cover URL actually returns an image (not a 1x1 placeholder).
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

  // ── Translation & Romanization ──

  /// Automatically translates and romanizes Japanese titles and authors.
  Future<Book> _applyTranslation(Book book) async {
    String? originalTitle;
    String? romajiTitle;
    String newTitle = book.title;

    String? originalAuthor;
    String? newAuthor = book.authors;

    // Process Title
    if (_isJapanese(book.title)) {
      originalTitle = book.title;
      // 1. Try Open Library for official English title
      final officialTitle = await _fetchOfficialTitle(book.title);
      if (officialTitle != null) {
        newTitle = officialTitle.toTitleCase();
        // Fallback romaji to title case google translate if possible
        final trans = await _translateJapaneseText(book.title);
        if (trans != null) romajiTitle = trans.$2?.toTitleCase();
      } else {
        // 2. Fallback to Google Translate
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

    // Process Author
    if (book.authors != null && _isJapanese(book.authors!)) {
      originalAuthor = book.authors;
      // 1. Try Open Library for official Author name
      final officialAuthor = await _fetchOfficialAuthorName(book.authors!);
      if (officialAuthor != null) {
        newAuthor = officialAuthor.toTitleCase();
      } else {
        // 2. Fallback to Google Translate
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

  /// Checks if a string contains Japanese Kanji, Hiragana, or Katakana.
  bool _isJapanese(String text) {
    return RegExp(r'[\u3000-\u303f\u3040-\u309f\u30a0-\u30ff\uff00-\uff9f\u4e00-\u9faf]').hasMatch(text);
  }

  /// Fetches translation and romaji using Google Translate's free web endpoint.
  /// Returns (English Translation, Romaji String) or null if failed.
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

      // Extract English translation (first item in the first inner list usually)
      final firstSection = sections.first as List<dynamic>?;
      if (firstSection != null && firstSection.isNotEmpty) {
        englishText = firstSection[0] as String?;
      }

      // Extract Romaji (often the last item in the sections list has the transliteration)
      final lastSection = sections.last as List<dynamic>?;
      if (lastSection != null && lastSection.length > 3) {
        romajiText = lastSection[3] as String?;
      }

      return (englishText, romajiText);
    } catch (_) {
      return null;
    }
  }

  /// Searches Open Library for an author and looks for an English/Romaji alternate name.
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

      // Find an alternate name that contains only ASCII characters (English/Romaji)
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

  /// Searches Open Library for a title and looks for an English alternate title.
  Future<String?> _fetchOfficialTitle(String japaneseTitle) async {
    try {
      final response = await _dio.get(
        'https://openlibrary.org/search.json',
        queryParameters: {'title': japaneseTitle},
      );
      final data = response.data;
      if (data['docs'] == null || (data['docs'] as List).isEmpty) return null;

      final doc = data['docs'][0];
      
      // Check alternate titles
      final alternates = doc['alternative_title'] as List<dynamic>?;
      if (alternates != null) {
        for (final alt in alternates) {
          final title = alt.toString();
          if (!_isJapanese(title) && RegExp(r'^[a-zA-Z0-9\s\.\-\:\,\!\?]+$').hasMatch(title)) {
            return title;
          }
        }
      }

      // If the main title of the best match is English, use that
      final mainTitle = doc['title']?.toString();
      if (mainTitle != null && !_isJapanese(mainTitle) && RegExp(r'^[a-zA-Z0-9\s\.\-\:\,\!\?]+$').hasMatch(mainTitle)) {
        return mainTitle;
      }

      return null;
    } catch (_) {
      return null;
    }
  }
}

extension StringCasingExtension on String {
  /// Converts a string to Title Case (e.g. "three days of happiness" -> "Three Days of Happiness")
  String toTitleCase() {
    if (trim().isEmpty) return this;
    final exceptions = {'a', 'an', 'the', 'and', 'but', 'or', 'for', 'nor', 'on', 'at', 'to', 'from', 'by', 'of', 'in'};
    
    return split(' ').asMap().map((index, word) {
      if (word.isEmpty) return MapEntry(index, '');
      final lowerWord = word.toLowerCase();
      // Capitalize first/last word, or if it's not in exceptions
      if (index == 0 || index == split(' ').length - 1 || !exceptions.contains(lowerWord)) {
        return MapEntry(index, word[0].toUpperCase() + lowerWord.substring(1));
      }
      return MapEntry(index, lowerWord);
    }).values.join(' ');
  }
}

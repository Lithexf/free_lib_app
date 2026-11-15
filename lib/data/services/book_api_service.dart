import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/book.dart';
import 'app_exceptions.dart';
import 'isbn_validator.dart';

class BookApiService {
  final Dio _dio;

  BookApiService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
              headers: {
                'User-Agent': 'FreeLib/1.0 (personal book library app)',
              },
            ));

  Future<Book?> lookupByIsbn(String rawIsbn) async {
    final isbn = IsbnValidator.normalize(rawIsbn);
    if (isbn == null) return null;

    final formats = _prioritizeIsbn13(IsbnValidator.getAllFormats(isbn));
    final primaryIsbn = formats.isNotEmpty ? formats.first : isbn;
    final tracker = _RequestHealthTracker();
    final isHungarian = IsbnValidator.isHungarianIsbn(primaryIsbn);

    if (isHungarian) {
      final parallelResults = await Future.wait<Book?>([
        _lookupBookline(primaryIsbn, tracker),
        _lookupGoogleBooks(primaryIsbn, tracker),
      ]);

      final booklineBook = parallelResults[0];
      final googleBook = parallelResults[1];

      if (booklineBook != null && googleBook != null) {
        return _applyTranslation(_mergeBooks(booklineBook, googleBook));
      }
      if (booklineBook != null) {
        return _applyTranslation(booklineBook);
      }
      if (googleBook != null) {
        if (_isMetadataIncomplete(googleBook) && !tracker.isOffline) {
          final antikBook = await _lookupAntikvarium(primaryIsbn, tracker);
          if (antikBook != null) {
            return _applyTranslation(_mergeBooks(googleBook, antikBook));
          }
        }
        return _applyTranslation(googleBook);
      }

      if (!tracker.isOffline) {
        final antikBook = await _lookupAntikvarium(primaryIsbn, tracker);
        if (antikBook != null) return _applyTranslation(antikBook);
      }

      if (!tracker.isOffline) {
        final openLibBook = await _lookupOpenLibraryCombined(formats, tracker);
        if (openLibBook != null) return _applyTranslation(openLibBook);
      }

      if (!tracker.isOffline) {
        final molyResult = await _lookupMoly(primaryIsbn, tracker);
        if (molyResult != null) return _applyTranslation(molyResult);
      }

      if (tracker.shouldThrowNetworkError) {
        throw const NetworkException();
      }
      return null;
    }

    Book? partialBook;

    for (final format in formats) {
      final googleBook = await _lookupGoogleBooks(format, tracker);
      if (googleBook != null) {
        if (!_isMetadataIncomplete(googleBook)) {
          return _applyTranslation(googleBook);
        }
        partialBook = googleBook;
        break;
      }
      if (tracker.isOffline || tracker.googleRateLimited) break;
    }

    if (!tracker.isOffline) {
      final openLibBook = await _lookupOpenLibraryCombined(formats, tracker);
      if (openLibBook != null) {
        final merged = partialBook != null
            ? _mergeBooks(partialBook, openLibBook)
            : openLibBook;
        return _applyTranslation(merged);
      }
    }

    if (partialBook != null) {
      return _applyTranslation(partialBook);
    }

    if (!tracker.isOffline) {
      final booklineBook = await _lookupBookline(primaryIsbn, tracker);
      if (booklineBook != null) return _applyTranslation(booklineBook);
    }

    if (!tracker.isOffline) {
      final antikBook = await _lookupAntikvarium(primaryIsbn, tracker);
      if (antikBook != null) return _applyTranslation(antikBook);
    }

    if (!tracker.isOffline) {
      final molyResult = await _lookupMoly(primaryIsbn, tracker);
      if (molyResult != null) return _applyTranslation(molyResult);
    }

    if (tracker.shouldThrowNetworkError) {
      throw const NetworkException();
    }

    return null;
  }

  bool _isMetadataIncomplete(Book book) {
    final hasAuthor = book.authors != null && book.authors!.trim().isNotEmpty;
    final hasCover = book.coverUrl != null && book.coverUrl!.trim().isNotEmpty;
    return !hasAuthor || !hasCover;
  }

  Book _mergeBooks(Book primary, Book secondary) {
    String? pickStr(String? a, String? b) =>
        (a != null && a.trim().isNotEmpty) ? a : b;

    final primaryTitleValid =
        primary.title.trim().isNotEmpty && primary.title != 'Ismeretlen cím';

    return primary.copyWith(
      title: primaryTitleValid ? primary.title : secondary.title,
      subtitle: pickStr(primary.subtitle, secondary.subtitle),
      authors: pickStr(primary.authors, secondary.authors),
      publisher: pickStr(primary.publisher, secondary.publisher),
      publishedDate: pickStr(primary.publishedDate, secondary.publishedDate),
      description: pickStr(primary.description, secondary.description),
      pageCount: primary.pageCount ?? secondary.pageCount,
      categories: pickStr(primary.categories, secondary.categories),
      coverUrl: pickStr(primary.coverUrl, secondary.coverUrl),
      externalRating: primary.externalRating ?? secondary.externalRating,
      externalRatingCount:
          primary.externalRatingCount ?? secondary.externalRatingCount,
      externalRatingSource:
          pickStr(primary.externalRatingSource, secondary.externalRatingSource),
      originalTitle: pickStr(primary.originalTitle, secondary.originalTitle),
      romajiTitle: pickStr(primary.romajiTitle, secondary.romajiTitle),
      originalAuthor: pickStr(primary.originalAuthor, secondary.originalAuthor),
    );
  }

  List<String> _prioritizeIsbn13(List<String> formats) {
    final sorted = List<String>.from(formats);
    sorted.sort((a, b) => b.length.compareTo(a.length));
    return sorted;
  }

  Future<List<Book>> searchBooksOnline(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final normalizedIsbn = IsbnValidator.normalize(trimmed);
    if (normalizedIsbn != null && IsbnValidator.isValid(normalizedIsbn)) {
      final exact = await lookupByIsbn(normalizedIsbn);
      if (exact != null) return [exact];
    }

    final tracker = _RequestHealthTracker();
    final results = <Book>[];
    final seenIsbns = <String>{};

    try {
      final response = await _dio.get(
        'https://www.googleapis.com/books/v1/volumes',
        queryParameters: {
          'q': trimmed,
          'maxResults': 15,
          'printType': 'books',
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

    if (results.isEmpty && !tracker.isOffline) {
      final booklineResults = await _searchBooklineOnline(trimmed, tracker);
      for (final book in booklineResults) {
        if (seenIsbns.add(book.isbn)) {
          results.add(book);
        }
      }
    }

    if (results.isEmpty && tracker.shouldThrowNetworkError) {
      throw const NetworkException();
    }

    return results;
  }

  Future<Book?> _lookupGoogleBooks(
    String isbn,
    _RequestHealthTracker tracker,
  ) async {
    try {
      final response = await _dio.get(
        'https://www.googleapis.com/books/v1/volumes',
        queryParameters: {'q': 'isbn:$isbn'},
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
      if (e.response?.statusCode == 429 || e.response?.statusCode == 403) {
        tracker.googleRateLimited = true;
        tracker.recordSuccess();
      } else {
        tracker.recordDioError(e);
      }
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

  Future<Book?> _lookupOpenLibraryCombined(
    List<String> formats,
    _RequestHealthTracker tracker,
  ) async {
    if (formats.isEmpty) return null;

    final editionBook = await _lookupOpenLibraryBatch(formats, tracker);
    if (editionBook != null) {
      final needsEnrichment =
          (editionBook.authors == null || editionBook.authors!.isEmpty) ||
              (editionBook.categories == null ||
                  editionBook.categories!.isEmpty) ||
              editionBook.externalRating == null;

      if (needsEnrichment && !tracker.isOffline) {
        final searchBook = await _searchOpenLibrary(formats.first, tracker);
        if (searchBook != null) {
          return _mergeOpenLibraryBooks(editionBook, searchBook);
        }
      }
      return editionBook;
    }

    if (!tracker.isOffline) {
      return _searchOpenLibrary(formats.first, tracker);
    }
    return null;
  }

  Book _mergeOpenLibraryBooks(Book editionBook, Book searchBook) {
    final merged = _mergeBooks(editionBook, searchBook);
    if (!_isJapanese(editionBook.title) && _isJapanese(searchBook.title)) {
      return merged.copyWith(
        title: editionBook.title,
        originalTitle: editionBook.originalTitle ?? searchBook.title,
      );
    }
    return merged;
  }

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

  Future<Book?> _lookupBookline(
    String isbn,
    _RequestHealthTracker tracker,
  ) async {
    try {
      final response = await _dio.get(
        'https://bookline.hu/search/search.action',
        queryParameters: {'searchfield': isbn},
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
          validateStatus: (status) => (status ?? 500) < 500,
          headers: {
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'hu-HU,hu;q=0.9,en-US;q=0.8,en;q=0.7',
          },
        ),
      );
      tracker.recordSuccess();

      final rawData = response.data;
      if (rawData is! String || rawData.isEmpty) return null;
      final html = rawData;

      if (html.contains('nem találtunk a keresésnek megfelelő') ||
          html.contains('Nincs találat')) {
        return null;
      }

      if (html.contains('itemprop="sku"')) {
        return _parseBooklineProductPage(isbn, html);
      }

      final cardIdx = html.indexOf('t-product-detailed');
      if (cardIdx == -1) return null;
      final cardEnd =
          (cardIdx + 6000 < html.length) ? cardIdx + 6000 : html.length;
      final cardHtml = html.substring(cardIdx, cardEnd);

      final parsedCard = _parseBooklineCard(cardHtml, explicitIsbn: isbn);
      if (parsedCard == null) return null;

      final book = parsedCard.$1;
      final productPath = parsedCard.$2;

      if (productPath != null && productPath.isNotEmpty) {
        try {
          final detailResp = await _dio.get(
            'https://bookline.hu$productPath',
            options: Options(
              responseType: ResponseType.plain,
              sendTimeout: const Duration(seconds: 3),
              receiveTimeout: const Duration(seconds: 3),
              validateStatus: (status) => (status ?? 500) < 500,
              headers: {
                'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
                'Accept-Language': 'hu-HU,hu;q=0.9',
              },
            ),
          );
          if (detailResp.data is String) {
            final detailHtml = detailResp.data as String;

            final skuMatch =
                RegExp(r'<span itemprop="sku">\s*([0-9Xx-]+)\s*</span>')
                    .firstMatch(detailHtml);
            if (skuMatch != null) {
              final pageSku = IsbnValidator.normalize(skuMatch.group(1)!) ??
                  skuMatch.group(1)!;
              final allowedFormats = IsbnValidator.getAllFormats(isbn);
              if (allowedFormats.isNotEmpty &&
                  !allowedFormats.contains(pageSku)) {
                return null;
              }
            }

            return _enrichBookFromBooklineDetail(book, detailHtml);
          }
        } catch (_) {}
      }

      return book;
    } on DioException catch (e) {
      tracker.recordDioError(e);
      return null;
    } catch (e) {
      debugPrint('Bookline lekérdezési hiba: $e');
      return null;
    }
  }

  Future<List<Book>> _searchBooklineOnline(
    String query,
    _RequestHealthTracker tracker,
  ) async {
    try {
      final response = await _dio.get(
        'https://bookline.hu/search/search.action',
        queryParameters: {'searchfield': query},
        options: Options(
          responseType: ResponseType.plain,
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
          validateStatus: (status) => (status ?? 500) < 500,
        ),
      );
      tracker.recordSuccess();

      final rawData = response.data;
      if (rawData is! String || rawData.isEmpty) return const [];
      if (rawData.contains('nem találtunk a keresésnek megfelelő')) {
        return const [];
      }

      final results = <Book>[];
      final parts = rawData.split('t-product-detailed');
      for (int i = 1; i < parts.length && results.length < 10; i++) {
        final snippet = parts[i].length > 6000
            ? parts[i].substring(0, 6000)
            : parts[i];
        final parsed = _parseBooklineCard(snippet, indexSeed: i);
        if (parsed != null) {
          results.add(parsed.$1);
        }
      }
      return results;
    } on DioException catch (e) {
      tracker.recordDioError(e);
      return const [];
    } catch (_) {
      return const [];
    }
  }

  (Book, String?)? _parseBooklineCard(
    String cardHtml, {
    String? explicitIsbn,
    int indexSeed = 0,
  }) {
    final titleMatch = RegExp(
      r'class="[^"]*o-product__title[^"]*"[^>]*>\s*([^<\s][^<]*)\s*<',
    ).firstMatch(cardHtml);
    if (titleMatch == null) return null;

    final rawTitle = _decodeHtmlEntities(titleMatch.group(1) ?? '').trim();
    if (rawTitle.isEmpty) return null;

    final authorMatch = RegExp(
      r'class="[^"]*o-product__author[^"]*"[^>]*>\s*([^<\s][^<]*)\s*<',
    ).firstMatch(cardHtml);
    final rawAuthor = _decodeHtmlEntities(authorMatch?.group(1) ?? '').trim();

    final linkMatch = RegExp(
      r'href="(/product/home\.action\?[^"]+)"',
    ).firstMatch(cardHtml);
    final productPath =
        linkMatch != null ? _decodeHtmlEntities(linkMatch.group(1)!) : null;

    String? publisher;
    String? publishedDate;
    final pubMatch = RegExp(
      r'<div class="o-product__publisher">\s*([^<]+)\s*</div>',
    ).firstMatch(cardHtml);
    if (pubMatch != null) {
      final pubText = _decodeHtmlEntities(pubMatch.group(1) ?? '').trim();
      final yearMatch = RegExp(r'^(.*),\s*(\d{4})$').firstMatch(pubText);
      if (yearMatch != null) {
        publisher = yearMatch.group(1)?.trim();
        publishedDate = yearMatch.group(2)?.trim();
      } else if (pubText.isNotEmpty) {
        publisher = pubText;
      }
    }

    String? coverUrl;
    final hiResCoverMatch = RegExp(
      r'(https://marvin\.bline\.hu/product_images/[^"\s,\]]+\.(?:JPG|jpg|jpeg|png|webp))',
    ).firstMatch(cardHtml);
    if (hiResCoverMatch != null) {
      coverUrl = hiResCoverMatch.group(1);
    } else {
      final fallbackCoverMatch = RegExp(
        r'src="(https://marvin\.bline\.hu/[^"]+\.(?:JPG|jpg|jpeg|png|webp))"',
      ).firstMatch(cardHtml);
      coverUrl = fallbackCoverMatch?.group(1);
    }

    double? externalRating;
    int? externalRatingCount;
    final starsMatch = RegExp(
      r'data-stars="([0-9.]+)"(?:\s+data-favcount="(\d+)")?',
    ).firstMatch(cardHtml);
    if (starsMatch != null) {
      final stars = double.tryParse(starsMatch.group(1) ?? '');
      if (stars != null && stars > 0) {
        externalRating = stars.clamp(0.0, 5.0);
        externalRatingCount = int.tryParse(starsMatch.group(2) ?? '');
      }
    }

    String? description;
    final leadMatch = RegExp(
      r'<p class="o-product__lead[^"]*">\s*([\s\S]*?)\s*</p>',
    ).firstMatch(cardHtml);
    if (leadMatch != null) {
      final cleanedLead = _stripHtmlTags(leadMatch.group(1) ?? '').trim();
      if (cleanedLead.isNotEmpty) {
        description = cleanedLead;
      }
    }

    final idMatch = RegExp(r'[?&]id=(\d+)').firstMatch(productPath ?? '');
    final resolvedIsbn = explicitIsbn ??
        'LOCAL-BL-${idMatch?.group(1) ?? '${DateTime.now().millisecondsSinceEpoch}-$indexSeed'}';

    final book = Book(
      isbn: resolvedIsbn,
      title: rawTitle,
      authors: rawAuthor.isEmpty ? null : rawAuthor,
      publisher: (publisher != null && publisher.isNotEmpty) ? publisher : null,
      publishedDate: publishedDate,
      description: description,
      coverUrl: coverUrl,
      dateAdded: DateTime.now(),
      externalRating: externalRating,
      externalRatingCount: externalRatingCount,
      externalRatingSource: externalRating != null ? 'Bookline' : null,
    );

    return (book, productPath);
  }

  Book? _parseBooklineProductPage(String isbn, String detailHtml) {
    final skuMatch = RegExp(r'<span itemprop="sku">\s*([0-9Xx-]+)\s*</span>')
        .firstMatch(detailHtml);
    if (skuMatch != null) {
      final pageSku =
          IsbnValidator.normalize(skuMatch.group(1)!) ?? skuMatch.group(1)!;
      final allowedFormats = IsbnValidator.getAllFormats(isbn);
      if (allowedFormats.isNotEmpty && !allowedFormats.contains(pageSku)) {
        return null;
      }
    }

    final titleMatch = RegExp(
      r'<h1[^>]*class="[^"]*o-product__title[^"]*"[^>]*>\s*([^<]+)\s*</h1>',
    ).firstMatch(detailHtml);
    final ogTitleMatch = RegExp(
      r'<meta\s+property="og:title"\s+content="([^"]+)"',
    ).firstMatch(detailHtml);

    String title = _decodeHtmlEntities(
      titleMatch?.group(1) ?? ogTitleMatch?.group(1) ?? '',
    ).trim();
    if (title.isEmpty) return null;

    final authorMatch = RegExp(
      r'class="[^"]*o-product__author[^"]*"[^>]*>\s*([^<\s][^<]*)\s*<',
    ).firstMatch(detailHtml);
    final author = _decodeHtmlEntities(authorMatch?.group(1) ?? '').trim();

    final baseBook = Book(
      isbn: isbn,
      title: title,
      authors: author.isEmpty ? null : author,
      dateAdded: DateTime.now(),
    );

    return _enrichBookFromBooklineDetail(baseBook, detailHtml);
  }

  Book _enrichBookFromBooklineDetail(Book book, String detailHtml) {
    int? pageCount = book.pageCount;
    final pageMatch = RegExp(r'(\d{2,5})\s*oldal', caseSensitive: false)
        .firstMatch(detailHtml);
    if (pageMatch != null) {
      pageCount = int.tryParse(pageMatch.group(1)!);
    }

    String? categories = book.categories;
    final catMatch = RegExp(r'Kategória:\s*([^,"<]+)').firstMatch(detailHtml);
    if (catMatch != null) {
      final cat = _decodeHtmlEntities(catMatch.group(1)!.trim());
      if (cat.isNotEmpty && !cat.toLowerCase().contains('ár:')) {
        categories = cat;
      }
    }

    String? description = book.description;
    final ogDescMatch = RegExp(
      r'<meta\s+property="og:description"\s+content="([^"]+)"\s*/?>',
    ).firstMatch(detailHtml);
    if (ogDescMatch != null) {
      final fullDesc = _decodeHtmlEntities(ogDescMatch.group(1)!.trim());
      if (fullDesc.isNotEmpty &&
          (description == null || fullDesc.length > description.length)) {
        description = fullDesc;
      }
    }

    String? originalTitle = book.originalTitle;
    final origTitleMatch =
        RegExp(r'<li>\s*Eredeti cím:\s*([^<]+)</li>').firstMatch(detailHtml);
    if (origTitleMatch != null) {
      final orig = _decodeHtmlEntities(origTitleMatch.group(1)!.trim());
      if (orig.isNotEmpty) {
        originalTitle = orig;
      }
    }

    String? coverUrl = book.coverUrl;
    if (coverUrl == null || coverUrl.isEmpty) {
      final ogImageMatch = RegExp(
        r'<meta\s+property="og:image"\s+content="([^"]+)"',
      ).firstMatch(detailHtml);
      coverUrl = ogImageMatch?.group(1)?.replaceAll('http://', 'https://');
    }

    return book.copyWith(
      pageCount: pageCount,
      categories: categories,
      description: description,
      originalTitle: originalTitle,
      coverUrl: coverUrl,
    );
  }

  Future<Book?> _lookupAntikvarium(
    String isbn,
    _RequestHealthTracker tracker,
  ) async {
    try {
      final response = await _dio.get(
        'https://www.antikvarium.hu/html/elasticAutoComplete.php',
        queryParameters: {
          'type': 'advanced',
          'keyword': isbn,
        },
        options: Options(
          responseType: ResponseType.plain,
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
          validateStatus: (status) => (status ?? 500) < 500,
          headers: {
            'Accept': 'text/html, */*;q=0.8',
            'Accept-Language': 'hu-HU,hu;q=0.9',
          },
        ),
      );
      tracker.recordSuccess();

      final rawData = response.data;
      if (rawData is! String || !rawData.contains('itemprop="name"')) {
        return null;
      }

      final titleMatch =
          RegExp(r'<span itemprop="name">\s*([^<]+)\s*</span>')
              .firstMatch(rawData);
      if (titleMatch == null) return null;

      final title = _decodeHtmlEntities(titleMatch.group(1) ?? '').trim();
      if (title.isEmpty) return null;

      final authorMatch =
          RegExp(r'<span itemprop="author">\s*([^<]+)\s*</span>')
              .firstMatch(rawData);
      final author = _decodeHtmlEntities(authorMatch?.group(1) ?? '').trim();

      String? coverUrl;
      final bigCoverMatch = RegExp(
        r'href="(https://cdn\.antikvarium\.hu/foto/nagy/[^"]+\.jpg)"',
      ).firstMatch(rawData);
      if (bigCoverMatch != null) {
        coverUrl = bigCoverMatch.group(1);
      } else {
        final thumbMatch = RegExp(
          r'data-original="(https://cdn\.antikvarium\.hu/foto/[^"]+\.jpg)"',
        ).firstMatch(rawData);
        coverUrl = thumbMatch?.group(1);
      }

      String? publisher;
      String? publishedDate;
      final infoBlockMatch = RegExp(
        r'<div class="ad-ac-box-item-book-info">([\s\S]*?)</div>',
      ).firstMatch(rawData);
      if (infoBlockMatch != null) {
        final spans = RegExp(r'<span(?:\s+[^>]*)?>\s*([^<]+)\s*</span>')
            .allMatches(infoBlockMatch.group(1)!)
            .map((m) => _decodeHtmlEntities(m.group(1) ?? '').trim())
            .where((s) => s.isNotEmpty && s != title && s != author)
            .toList();

        for (final s in spans) {
          if (RegExp(r'^\d{4}$').hasMatch(s)) {
            publishedDate ??= s;
          } else {
            publisher ??= s;
          }
        }
      }

      return Book(
        isbn: isbn,
        title: title,
        authors: author.isEmpty ? null : author,
        publisher: publisher,
        publishedDate: publishedDate,
        coverUrl: coverUrl,
        dateAdded: DateTime.now(),
      );
    } on DioException catch (e) {
      tracker.recordDioError(e);
      return null;
    } catch (e) {
      debugPrint('Antikvarium lekérdezési hiba: $e');
      return null;
    }
  }

  Future<Book?> _lookupMoly(
    String isbn,
    _RequestHealthTracker tracker,
  ) async {
    try {
      final response = await _dio.get(
        'https://moly.hu/kereses',
        queryParameters: {'q': isbn},
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
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

      var titleMatch =
          RegExp(r'<title>(.*?) · Moly<\/title>').firstMatch(html);
      if (titleMatch == null) return null;

      var pageTitle = _decodeHtmlEntities(titleMatch.group(1) ?? '').trim();

      if (pageTitle.isEmpty || pageTitle.startsWith('Keresés')) {
        final bookLinkMatch =
            RegExp(r'href="(\/konyvek\/[^"#?]+)"').firstMatch(html);
        if (bookLinkMatch == null) return null;

        final bookPath = bookLinkMatch.group(1)!;
        final bookPageResp = await _dio.get(
          'https://moly.hu$bookPath',
          options: Options(
            responseType: ResponseType.plain,
            sendTimeout: const Duration(seconds: 4),
            receiveTimeout: const Duration(seconds: 4),
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

      final coverMatch = RegExp(
              r'(https:\/\/moly\.hu\/system\/covers\/big\/.*?\.jpg)')
          .firstMatch(html);
      final String? coverUrl = coverMatch?.group(1);

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

  String _stripHtmlTags(String htmlText) {
    final withoutTags = htmlText.replaceAll(RegExp(r'<[^>]*>'), ' ');
    return _decodeHtmlEntities(withoutTags).replaceAll(RegExp(r'\s+'), ' ');
  }

  String _decodeHtmlEntities(String input) {
    var result = input
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#039;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&ndash;', '-')
        .replaceAll('&mdash;', '-')
        .replaceAll('&nbsp;', ' ');

    result = result.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      final code = int.tryParse(match.group(1) ?? '');
      return code != null ? String.fromCharCode(code) : match.group(0)!;
    });
    result = result.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
      final code = int.tryParse(match.group(1) ?? '', radix: 16);
      return code != null ? String.fromCharCode(code) : match.group(0)!;
    });

    return result;
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
      coverUrl = coverUrl
          .replaceAll('-S.jpg', '-L.jpg')
          .replaceAll('http://', 'https://');
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
      authors: (authors != null && authors.isNotEmpty) ? authors : null,
      publisher: publisher,
      publishedDate: details['publish_date'] as String?,
      description: description,
      pageCount: pageCount,
      categories:
          (categories != null && categories.isNotEmpty) ? categories : null,
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

  Future<Book> _applyTranslation(Book book) async {
    String? originalTitle = book.originalTitle;
    String? romajiTitle = book.romajiTitle;
    String newTitle = book.title;

    String? originalAuthor = book.originalAuthor;
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
  bool googleRateLimited = false;

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

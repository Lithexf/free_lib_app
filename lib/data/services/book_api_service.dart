import 'package:dio/dio.dart';
import '../models/book.dart';
import 'isbn_validator.dart';

/// Service for fetching book metadata from external APIs.
///
/// Uses a layered fallback strategy:
/// 1. Google Books API (richer metadata, includes community ratings)
/// 2. Open Library API (free, no key needed)
/// 3. Open Library Covers API (direct URL construction)
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

  /// Look up a book by ISBN. Returns a partially-filled Book object, or null.
  Future<Book?> lookupByIsbn(String rawIsbn) async {
    final isbn = IsbnValidator.normalize(rawIsbn);
    if (isbn == null) return null;

    // Try Google Books first (works without API key for standard queries)
    final googleResult = await _lookupGoogleBooks(isbn);
    if (googleResult != null) return googleResult;

    // Fall back to Open Library
    final openLibResult = await _lookupOpenLibrary(isbn);
    return openLibResult;
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
        coverUrl = (imageLinks['thumbnail'] as String?)
            ?.replaceAll('http://', 'https://');
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
      // Network error — fall through to next provider
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Open Library API ──

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
        // Upgrade from small to large
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
        description: null, // Open Library details don't include description here
        pageCount: pageCount,
        categories: categories,
        coverUrl: coverUrl,
        dateAdded: DateTime.now(),
        externalRating: externalRating,
        externalRatingCount: externalRatingCount,
        externalRatingSource: externalRatingSource,
      );
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Extract the Open Library works key from book details.
  /// The `works` field contains entries like `{"key": "/works/OL12345W"}`.
  String? _extractWorksKey(Map<String, dynamic> details) {
    try {
      final works = details['works'] as List<dynamic>?;
      if (works == null || works.isEmpty) return null;
      final firstWork = works.first as Map<String, dynamic>;
      final key = firstWork['key'] as String?; // e.g. "/works/OL12345W"
      return key;
    } catch (_) {
      return null;
    }
  }

  /// Fetch community ratings from Open Library's ratings API.
  /// Returns (averageRating, ratingsCount) or null if unavailable.
  Future<(double, int)?> _fetchOpenLibraryRatings(String worksKey) async {
    try {
      // worksKey is like "/works/OL12345W"
      final response = await _dio.get(
        'https://openlibrary.org$worksKey/ratings.json',
      );

      final data = response.data as Map<String, dynamic>;
      final summary = data['summary'] as Map<String, dynamic>?;
      if (summary == null) return null;

      final average = (summary['average'] as num?)?.toDouble();
      final count = summary['count'] as int? ?? 0;

      if (average == null || average <= 0 || count == 0) return null;

      // Open Library ratings are on a 1–5 scale
      return (average, count);
    } catch (_) {
      return null;
    }
  }

  /// Build a direct Open Library cover URL from ISBN.
  /// No API call needed — just construct the URL.
  String _buildOpenLibraryCoverUrl(String isbn) {
    return 'https://covers.openlibrary.org/b/isbn/$isbn-L.jpg';
  }

  /// Check if a cover URL actually returns an image (not a 1x1 placeholder).
  /// Open Library returns a 1x1 transparent pixel for missing covers.
  Future<bool> isCoverAvailable(String url) async {
    try {
      final response = await _dio.head(url);
      final contentLength =
          int.tryParse(response.headers.value('content-length') ?? '0') ?? 0;
      // Open Library's placeholder is ~43 bytes; real covers are much larger
      return contentLength > 1000;
    } catch (_) {
      return false;
    }
  }
}

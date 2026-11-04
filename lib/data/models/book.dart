/// Core Book model for the FreeLib application.
///
/// Represents a single book in the user's library, including
/// metadata fetched from APIs and user-specific data like ratings, progress, and status.
class Book {
  static const Object _unset = Object();

  final int? id;
  final String isbn;
  final String title;
  final String? subtitle;
  final String? authors;
  final String? publisher;
  final String? publishedDate;
  final String? description;
  final int? pageCount;
  final int? currentPage;
  final String? categories;
  final String? coverUrl;
  final double? rating;
  final String status; // ReadingStatus.name stored as string
  final DateTime dateAdded;
  final DateTime? dateStarted;
  final DateTime? dateFinished;
  final String? notes;

  // ── Original (Japanese) metadata ──
  /// The original Japanese title (stored for searching)
  final String? originalTitle;

  /// The romanized (Romaji) title (stored for searching and display)
  final String? romajiTitle;

  /// The original Japanese author (stored for searching)
  final String? originalAuthor;

  // ── External (community) rating data ──
  /// Average rating from external source (Google Books / Open Library / Moly.hu), 1.0–5.0 scale
  final double? externalRating;

  /// Number of ratings from the external source
  final int? externalRatingCount;

  /// Name of the external rating source (e.g. "Google Books", "Open Library", "Moly.hu")
  final String? externalRatingSource;

  const Book({
    this.id,
    required this.isbn,
    required this.title,
    this.subtitle,
    this.authors,
    this.publisher,
    this.publishedDate,
    this.description,
    this.pageCount,
    this.currentPage,
    this.categories,
    this.coverUrl,
    this.rating,
    this.status = 'planToRead',
    required this.dateAdded,
    this.dateStarted,
    this.dateFinished,
    this.notes,
    this.originalTitle,
    this.romajiTitle,
    this.originalAuthor,
    this.externalRating,
    this.externalRatingCount,
    this.externalRatingSource,
  });

  /// Returns reading progress between 0.0 and 1.0 if page count and current page are available.
  double? get readingProgress {
    if (pageCount == null || pageCount! <= 0) return null;
    if (status == 'completed') return 1.0;
    if (currentPage == null || currentPage! <= 0) return 0.0;
    return (currentPage! / pageCount!).clamp(0.0, 1.0);
  }

  /// True if the ISBN was generated locally for a manually added book without a barcode.
  bool get isManualIsbn => isbn.startsWith('LOCAL-');

  /// Create a Book from a JSON map (database row or API response)
  factory Book.fromMap(Map<String, dynamic> map) {
    return Book(
      id: map['id'] as int?,
      isbn: map['isbn'] as String,
      title: map['title'] as String,
      subtitle: map['subtitle'] as String?,
      authors: map['authors'] as String?,
      publisher: map['publisher'] as String?,
      publishedDate: map['published_date'] as String?,
      description: map['description'] as String?,
      pageCount: (map['page_count'] as num?)?.toInt(),
      currentPage: (map['current_page'] as num?)?.toInt(),
      categories: map['categories'] as String?,
      coverUrl: map['cover_url'] as String?,
      rating: (map['rating'] as num?)?.toDouble(),
      status: (map['status'] as String?) ?? 'planToRead',
      dateAdded: DateTime.fromMillisecondsSinceEpoch(
        (map['date_added'] as num).toInt(),
      ),
      dateStarted: map['date_started'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['date_started'] as num).toInt(),
            )
          : null,
      dateFinished: map['date_finished'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['date_finished'] as num).toInt(),
            )
          : null,
      notes: map['notes'] as String?,
      originalTitle: map['original_title'] as String?,
      romajiTitle: map['romaji_title'] as String?,
      originalAuthor: map['original_author'] as String?,
      externalRating: (map['external_rating'] as num?)?.toDouble(),
      externalRatingCount: (map['external_rating_count'] as num?)?.toInt(),
      externalRatingSource: map['external_rating_source'] as String?,
    );
  }

  /// Convert to a map for database insertion
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'isbn': isbn,
      'title': title,
      'subtitle': subtitle,
      'authors': authors,
      'publisher': publisher,
      'published_date': publishedDate,
      'description': description,
      'page_count': pageCount,
      'current_page': currentPage,
      'categories': categories,
      'cover_url': coverUrl,
      'rating': rating,
      'status': status,
      'date_added': dateAdded.millisecondsSinceEpoch,
      'date_started': dateStarted?.millisecondsSinceEpoch,
      'date_finished': dateFinished?.millisecondsSinceEpoch,
      'notes': notes,
      'original_title': originalTitle,
      'romaji_title': romajiTitle,
      'original_author': originalAuthor,
      'external_rating': externalRating,
      'external_rating_count': externalRatingCount,
      'external_rating_source': externalRatingSource,
    };
  }

  /// Create a copy with overridden fields.
  /// Supports explicitly passing `null` to clear nullable fields.
  Book copyWith({
    int? id,
    String? isbn,
    String? title,
    Object? subtitle = _unset,
    Object? authors = _unset,
    Object? publisher = _unset,
    Object? publishedDate = _unset,
    Object? description = _unset,
    Object? pageCount = _unset,
    Object? currentPage = _unset,
    Object? categories = _unset,
    Object? coverUrl = _unset,
    Object? rating = _unset,
    String? status,
    DateTime? dateAdded,
    Object? dateStarted = _unset,
    Object? dateFinished = _unset,
    Object? notes = _unset,
    Object? originalTitle = _unset,
    Object? romajiTitle = _unset,
    Object? originalAuthor = _unset,
    Object? externalRating = _unset,
    Object? externalRatingCount = _unset,
    Object? externalRatingSource = _unset,
  }) {
    return Book(
      id: id ?? this.id,
      isbn: isbn ?? this.isbn,
      title: title ?? this.title,
      subtitle: identical(subtitle, _unset) ? this.subtitle : subtitle as String?,
      authors: identical(authors, _unset) ? this.authors : authors as String?,
      publisher: identical(publisher, _unset) ? this.publisher : publisher as String?,
      publishedDate: identical(publishedDate, _unset)
          ? this.publishedDate
          : publishedDate as String?,
      description:
          identical(description, _unset) ? this.description : description as String?,
      pageCount: identical(pageCount, _unset) ? this.pageCount : pageCount as int?,
      currentPage:
          identical(currentPage, _unset) ? this.currentPage : currentPage as int?,
      categories:
          identical(categories, _unset) ? this.categories : categories as String?,
      coverUrl: identical(coverUrl, _unset) ? this.coverUrl : coverUrl as String?,
      rating: identical(rating, _unset) ? this.rating : rating as double?,
      status: status ?? this.status,
      dateAdded: dateAdded ?? this.dateAdded,
      dateStarted: identical(dateStarted, _unset)
          ? this.dateStarted
          : dateStarted as DateTime?,
      dateFinished: identical(dateFinished, _unset)
          ? this.dateFinished
          : dateFinished as DateTime?,
      notes: identical(notes, _unset) ? this.notes : notes as String?,
      originalTitle: identical(originalTitle, _unset)
          ? this.originalTitle
          : originalTitle as String?,
      romajiTitle: identical(romajiTitle, _unset)
          ? this.romajiTitle
          : romajiTitle as String?,
      originalAuthor: identical(originalAuthor, _unset)
          ? this.originalAuthor
          : originalAuthor as String?,
      externalRating: identical(externalRating, _unset)
          ? this.externalRating
          : externalRating as double?,
      externalRatingCount: identical(externalRatingCount, _unset)
          ? this.externalRatingCount
          : externalRatingCount as int?,
      externalRatingSource: identical(externalRatingSource, _unset)
          ? this.externalRatingSource
          : externalRatingSource as String?,
    );
  }

  @override
  String toString() => 'Book(id: $id, isbn: $isbn, title: $title)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Book &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          isbn == other.isbn;

  @override
  int get hashCode => Object.hash(id, isbn);
}

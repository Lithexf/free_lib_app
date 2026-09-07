/// Core Book model for the FreeLib application.
///
/// Represents a single book in the user's library, including
/// metadata fetched from APIs and user-specific data like ratings and status.
class Book {
  final int? id;
  final String isbn;
  final String title;
  final String? subtitle;
  final String? authors;
  final String? publisher;
  final String? publishedDate;
  final String? description;
  final int? pageCount;
  final String? categories;
  final String? coverUrl;
  final double? rating;
  final String status; // ReadingStatus.name stored as string
  final DateTime dateAdded;
  final DateTime? dateStarted;
  final DateTime? dateFinished;
  final String? notes;

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
    this.categories,
    this.coverUrl,
    this.rating,
    this.status = 'planToRead',
    required this.dateAdded,
    this.dateStarted,
    this.dateFinished,
    this.notes,
  });

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
      pageCount: map['page_count'] as int?,
      categories: map['categories'] as String?,
      coverUrl: map['cover_url'] as String?,
      rating: map['rating'] as double?,
      status: (map['status'] as String?) ?? 'planToRead',
      dateAdded: DateTime.fromMillisecondsSinceEpoch(map['date_added'] as int),
      dateStarted: map['date_started'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['date_started'] as int)
          : null,
      dateFinished: map['date_finished'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['date_finished'] as int)
          : null,
      notes: map['notes'] as String?,
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
      'categories': categories,
      'cover_url': coverUrl,
      'rating': rating,
      'status': status,
      'date_added': dateAdded.millisecondsSinceEpoch,
      'date_started': dateStarted?.millisecondsSinceEpoch,
      'date_finished': dateFinished?.millisecondsSinceEpoch,
      'notes': notes,
    };
  }

  /// Create a copy with overridden fields
  Book copyWith({
    int? id,
    String? isbn,
    String? title,
    String? subtitle,
    String? authors,
    String? publisher,
    String? publishedDate,
    String? description,
    int? pageCount,
    String? categories,
    String? coverUrl,
    double? rating,
    String? status,
    DateTime? dateAdded,
    DateTime? dateStarted,
    DateTime? dateFinished,
    String? notes,
  }) {
    return Book(
      id: id ?? this.id,
      isbn: isbn ?? this.isbn,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      authors: authors ?? this.authors,
      publisher: publisher ?? this.publisher,
      publishedDate: publishedDate ?? this.publishedDate,
      description: description ?? this.description,
      pageCount: pageCount ?? this.pageCount,
      categories: categories ?? this.categories,
      coverUrl: coverUrl ?? this.coverUrl,
      rating: rating ?? this.rating,
      status: status ?? this.status,
      dateAdded: dateAdded ?? this.dateAdded,
      dateStarted: dateStarted ?? this.dateStarted,
      dateFinished: dateFinished ?? this.dateFinished,
      notes: notes ?? this.notes,
    );
  }

  @override
  String toString() => 'Book(id: $id, isbn: $isbn, title: $title)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Book && runtimeType == other.runtimeType && id == other.id && isbn == other.isbn;

  @override
  int get hashCode => id.hashCode ^ isbn.hashCode;
}

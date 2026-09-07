import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database/app_database.dart';
import '../data/models/book.dart';
import '../data/services/book_api_service.dart';
import 'database_provider.dart';

/// Sort options for the book library
enum BookSortOrder {
  dateAddedDesc('Recently Added'),
  dateAddedAsc('Oldest First'),
  titleAsc('Title A–Z'),
  titleDesc('Title Z–A'),
  ratingDesc('Highest Rated'),
  ratingAsc('Lowest Rated');

  const BookSortOrder(this.label);
  final String label;

  String get sqlOrderBy {
    switch (this) {
      case BookSortOrder.dateAddedDesc:
        return 'date_added DESC';
      case BookSortOrder.dateAddedAsc:
        return 'date_added ASC';
      case BookSortOrder.titleAsc:
        return 'title ASC';
      case BookSortOrder.titleDesc:
        return 'title DESC';
      case BookSortOrder.ratingDesc:
        return 'rating DESC';
      case BookSortOrder.ratingAsc:
        return 'rating ASC';
    }
  }
}

/// Current sort order state
final bookSortOrderProvider = StateProvider<BookSortOrder>((ref) {
  return BookSortOrder.dateAddedDesc;
});

/// Current status filter (null = show all)
final statusFilterProvider = StateProvider<String?>((ref) {
  return null;
});

/// Search query state
final searchQueryProvider = StateProvider<String>((ref) {
  return '';
});

/// Notifier that manages the book library and triggers refreshes
class BookListNotifier extends AsyncNotifier<List<Book>> {
  @override
  Future<List<Book>> build() async {
    return _fetchBooks();
  }

  Future<List<Book>> _fetchBooks() async {
    final db = ref.read(databaseProvider);
    final sortOrder = ref.read(bookSortOrderProvider);
    final statusFilter = ref.read(statusFilterProvider);
    final searchQuery = ref.read(searchQueryProvider);

    if (searchQuery.isNotEmpty) {
      return db.searchBooks(searchQuery);
    }

    if (statusFilter != null) {
      return db.getBooksByStatus(statusFilter, orderBy: sortOrder.sqlOrderBy);
    }

    return db.getAllBooks(orderBy: sortOrder.sqlOrderBy);
  }

  /// Refresh the book list from database
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchBooks());
  }

  /// Add a new book to the library
  Future<Book?> addBook(Book book) async {
    final db = ref.read(databaseProvider);

    // Check if already exists
    final existing = await db.getBookByIsbn(book.isbn);
    if (existing != null) return existing;

    final id = await db.insertBook(book);
    await refresh();
    return book.copyWith(id: id);
  }

  /// Update an existing book
  Future<void> updateBook(Book book) async {
    final db = ref.read(databaseProvider);
    await db.updateBook(book);
    await refresh();
  }

  /// Delete a book
  Future<void> deleteBook(int id) async {
    final db = ref.read(databaseProvider);
    await db.deleteBook(id);
    await refresh();
  }

  /// Scan and add: look up ISBN, fetch metadata, add to library
  Future<Book?> scanAndAdd(String isbn) async {
    final apiService = ref.read(bookApiServiceProvider);
    final db = ref.read(databaseProvider);

    // Check if already in library
    final existing = await db.getBookByIsbn(isbn);
    if (existing != null) return existing;

    // Fetch metadata from APIs
    final book = await apiService.lookupByIsbn(isbn);
    if (book == null) return null;

    final id = await db.insertBook(book);
    await refresh();
    return book.copyWith(id: id);
  }
}

/// The main book list provider
final bookListProvider =
    AsyncNotifierProvider<BookListNotifier, List<Book>>(BookListNotifier.new);

/// Statistics provider
final bookStatsProvider = FutureProvider<BookStats>((ref) async {
  // Depend on book list so stats refresh when books change
  ref.watch(bookListProvider);

  final db = ref.read(databaseProvider);
  final totalCount = await db.getTotalBookCount();
  final countByStatus = await db.getBookCountByStatus();
  final avgRating = await db.getAverageRating();
  final booksPerMonth = await db.getBooksAddedPerMonth();

  return BookStats(
    totalCount: totalCount,
    countByStatus: countByStatus,
    averageRating: avgRating,
    booksAddedPerMonth: booksPerMonth,
  );
});

/// Immutable statistics data class
class BookStats {
  final int totalCount;
  final Map<String, int> countByStatus;
  final double averageRating;
  final List<Map<String, dynamic>> booksAddedPerMonth;

  const BookStats({
    required this.totalCount,
    required this.countByStatus,
    required this.averageRating,
    required this.booksAddedPerMonth,
  });
}

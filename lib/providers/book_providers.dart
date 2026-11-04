import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/book.dart';
import 'database_provider.dart';

/// Sort options for the book library
enum BookSortOrder {
  dateAddedDesc('Legutóbb hozzáadott'),
  dateAddedAsc('Legrégebbi elöl'),
  titleAsc('Cím A–Z'),
  titleDesc('Cím Z–A'),
  ratingDesc('Legjobbra értékelt'),
  ratingAsc('Legrosszabbra értékelt');

  const BookSortOrder(this.label);
  final String label;

  String get sqlOrderBy {
    switch (this) {
      case BookSortOrder.dateAddedDesc:
        return 'date_added DESC';
      case BookSortOrder.dateAddedAsc:
        return 'date_added ASC';
      case BookSortOrder.titleAsc:
        return 'title COLLATE NOCASE ASC';
      case BookSortOrder.titleDesc:
        return 'title COLLATE NOCASE DESC';
      case BookSortOrder.ratingDesc:
        return 'CASE WHEN rating IS NULL OR rating <= 0 THEN 1 ELSE 0 END, rating DESC';
      case BookSortOrder.ratingAsc:
        return 'CASE WHEN rating IS NULL OR rating <= 0 THEN 1 ELSE 0 END, rating ASC';
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

/// Notifier that manages the book library and reacts to filter/search/sort changes
class BookListNotifier extends AsyncNotifier<List<Book>> {
  @override
  Future<List<Book>> build() async {
    final sortOrder = ref.watch(bookSortOrderProvider);
    final statusFilter = ref.watch(statusFilterProvider);
    final searchQuery = ref.watch(searchQueryProvider);

    final db = ref.watch(databaseProvider);
    return db.queryBooks(
      searchQuery: searchQuery,
      status: statusFilter,
      orderBy: sortOrder.sqlOrderBy,
    );
  }

  Future<List<Book>> _fetchCurrent() {
    final db = ref.read(databaseProvider);
    final sortOrder = ref.read(bookSortOrderProvider);
    final statusFilter = ref.read(statusFilterProvider);
    final searchQuery = ref.read(searchQueryProvider);
    return db.queryBooks(
      searchQuery: searchQuery,
      status: statusFilter,
      orderBy: sortOrder.sqlOrderBy,
    );
  }

  /// Refresh the book list and statistics from database
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetchCurrent);
    ref.invalidate(bookStatsProvider);
  }

  /// Add a new book to the library
  Future<Book> addBook(Book book) async {
    final db = ref.read(databaseProvider);

    // Check if already exists (checks ISBN-10 & ISBN-13 variants)
    final existing = await db.getBookByIsbn(book.isbn);
    if (existing != null) return existing;

    final id = await db.insertBook(book);
    await refresh();
    return book.copyWith(id: id);
  }

  /// Update an existing book
  Future<Book> updateBook(Book book) async {
    final db = ref.read(databaseProvider);
    await db.updateBook(book);
    await refresh();
    return book;
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

    // Fetch metadata from APIs (may throw NetworkException if offline)
    final book = await apiService.lookupByIsbn(isbn);
    if (book == null) return null;

    // Re-check with normalized/resolved ISBN returned by the API
    final resolvedExisting = await db.getBookByIsbn(book.isbn);
    if (resolvedExisting != null) return resolvedExisting;

    final id = await db.insertBook(book);
    await refresh();
    return book.copyWith(id: id);
  }
}

/// The main book list provider
final bookListProvider =
    AsyncNotifierProvider<BookListNotifier, List<Book>>(BookListNotifier.new);

/// Notifier for managing the user's annual reading goal (persisted in SQLite)
class YearlyGoalNotifier extends AsyncNotifier<int> {
  static const String _settingKey = 'yearly_reading_goal';
  static const int defaultGoal = 12;

  @override
  Future<int> build() async {
    final db = ref.watch(databaseProvider);
    final stored = await db.getSetting(_settingKey);
    final parsed = int.tryParse(stored ?? '');
    return (parsed != null && parsed > 0) ? parsed : defaultGoal;
  }

  Future<void> updateGoal(int newGoal) async {
    final clamped = newGoal.clamp(1, 500);
    final db = ref.read(databaseProvider);
    await db.setSetting(_settingKey, '$clamped');
    state = AsyncData(clamped);
    ref.invalidate(bookStatsProvider);
  }
}

final yearlyGoalProvider =
    AsyncNotifierProvider<YearlyGoalNotifier, int>(YearlyGoalNotifier.new);

/// Statistics provider (independent of active UI search/status filters)
final bookStatsProvider = FutureProvider<BookStats>((ref) async {
  final db = ref.watch(databaseProvider);
  final yearlyGoal = await ref.watch(yearlyGoalProvider.future);

  final totalCount = await db.getTotalBookCount();
  final countByStatus = await db.getBookCountByStatus();
  final avgRating = await db.getAverageRating();
  final totalPagesRead = await db.getTotalPagesRead();
  final completedThisYear = await db.getBooksCompletedThisYear();
  final booksPerMonth = await db.getBooksAddedPerMonth();

  return BookStats(
    totalCount: totalCount,
    countByStatus: countByStatus,
    averageRating: avgRating,
    totalPagesRead: totalPagesRead,
    completedThisYear: completedThisYear,
    yearlyGoal: yearlyGoal,
    booksAddedPerMonth: booksPerMonth,
  );
});

/// Immutable statistics data class
class BookStats {
  final int totalCount;
  final Map<String, int> countByStatus;
  final double averageRating;
  final int totalPagesRead;
  final int completedThisYear;
  final int yearlyGoal;
  final List<Map<String, dynamic>> booksAddedPerMonth;

  const BookStats({
    required this.totalCount,
    required this.countByStatus,
    required this.averageRating,
    this.totalPagesRead = 0,
    this.completedThisYear = 0,
    this.yearlyGoal = 12,
    required this.booksAddedPerMonth,
  });
}

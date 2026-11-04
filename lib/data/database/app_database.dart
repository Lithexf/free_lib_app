import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/book.dart';
import '../services/app_exceptions.dart';
import '../services/isbn_validator.dart';

/// SQLite database helper for the FreeLib app.
///
/// Uses sqflite to provide full CRUD, combined filtering/searching/sorting,
/// reading goal persistence, and statistics queries with structured error handling.
class AppDatabase {
  static AppDatabase? _instance;
  static Database? _database;

  AppDatabase._();

  static AppDatabase get instance {
    _instance ??= AppDatabase._();
    return _instance!;
  }

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = p.join(dir.path, 'freelib.db');
      return await openDatabase(
        path,
        version: 4,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      throw StorageException(
        'Nem sikerült megnyitni a helyi adatbázist.',
        e,
      );
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        isbn TEXT NOT NULL UNIQUE,
        title TEXT NOT NULL,
        subtitle TEXT,
        authors TEXT,
        publisher TEXT,
        published_date TEXT,
        description TEXT,
        page_count INTEGER,
        current_page INTEGER,
        categories TEXT,
        cover_url TEXT,
        rating REAL,
        status TEXT NOT NULL DEFAULT 'planToRead',
        date_added INTEGER NOT NULL,
        date_started INTEGER,
        date_finished INTEGER,
        notes TEXT,
        original_title TEXT,
        romaji_title TEXT,
        original_author TEXT,
        external_rating REAL,
        external_rating_count INTEGER,
        external_rating_source TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Indexes for fast status filtering and search
    await db.execute('CREATE INDEX idx_books_status ON books (status)');
    await db.execute('CREATE INDEX idx_books_title ON books (title)');
    await db.execute('CREATE INDEX idx_books_isbn ON books (isbn)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v2: Add external (community) rating columns
      await db.execute('ALTER TABLE books ADD COLUMN external_rating REAL');
      await db.execute(
          'ALTER TABLE books ADD COLUMN external_rating_count INTEGER');
      await db.execute(
          'ALTER TABLE books ADD COLUMN external_rating_source TEXT');
    }
    if (oldVersion < 3) {
      // v3: Add original Japanese title and author columns for translation/search
      await db.execute('ALTER TABLE books ADD COLUMN original_title TEXT');
      await db.execute('ALTER TABLE books ADD COLUMN romaji_title TEXT');
      await db.execute('ALTER TABLE books ADD COLUMN original_author TEXT');
    }
    if (oldVersion < 4) {
      // v4: Add current_page for reading progress tracking + app_settings table
      await db.execute('ALTER TABLE books ADD COLUMN current_page INTEGER');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
  }

  // ── CRUD Operations ──

  /// Insert a new book safely without overwriting existing user data.
  /// Returns the newly inserted row id.
  Future<int> insertBook(Book book) async {
    try {
      final existing = await getBookByIsbn(book.isbn);
      if (existing != null) {
        throw DuplicateBookException(
          isbn: existing.isbn,
          existingTitle: existing.title,
        );
      }

      final db = await database;
      return await db.insert(
        'books',
        book.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } on AppException {
      rethrow;
    } catch (e) {
      throw StorageException('Nem sikerült elmenteni a könyvet.', e);
    }
  }

  /// Update an existing book. Returns number of rows affected.
  Future<int> updateBook(Book book) async {
    if (book.id == null) {
      throw const StorageException('A frissítendő könyvnek nincs azonosítója.');
    }
    try {
      final db = await database;
      return await db.update(
        'books',
        book.toMap(),
        where: 'id = ?',
        whereArgs: [book.id],
      );
    } catch (e) {
      throw StorageException('Nem sikerült frissíteni a könyv adatait.', e);
    }
  }

  /// Delete a book by id. Returns number of rows affected.
  Future<int> deleteBook(int id) async {
    try {
      final db = await database;
      return await db.delete(
        'books',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      throw StorageException('Nem sikerült törölni a könyvet.', e);
    }
  }

  /// Get a single book by id.
  Future<Book?> getBook(int id) async {
    try {
      final db = await database;
      final maps = await db.query(
        'books',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (maps.isEmpty) return null;
      return Book.fromMap(maps.first);
    } catch (e) {
      throw StorageException('Nem sikerült lekérdezni a könyvet.', e);
    }
  }

  /// Get a single book by ISBN (checking both ISBN-10 and ISBN-13 variants).
  Future<Book?> getBookByIsbn(String isbn) async {
    try {
      final db = await database;
      final variants = isbn.startsWith('LOCAL-')
          ? <String>[isbn]
          : IsbnValidator.getAllFormats(isbn);
      if (variants.isEmpty) return null;

      final placeholders = List.filled(variants.length, '?').join(', ');
      final maps = await db.query(
        'books',
        where: 'isbn IN ($placeholders)',
        whereArgs: variants,
      );
      if (maps.isEmpty) return null;
      return Book.fromMap(maps.first);
    } catch (e) {
      throw StorageException('Nem sikerült ellenőrizni az ISBN-t.', e);
    }
  }

  // ── Query Operations ──

  /// Unified query supporting combined search query, status filter, and sort order.
  Future<List<Book>> queryBooks({
    String? searchQuery,
    String? status,
    String orderBy = 'date_added DESC',
  }) async {
    try {
      final db = await database;
      final whereClauses = <String>[];
      final whereArgs = <Object?>[];

      if (status != null && status.isNotEmpty) {
        whereClauses.add('status = ?');
        whereArgs.add(status);
      }

      final trimmedQuery = searchQuery?.trim() ?? '';
      if (trimmedQuery.isNotEmpty) {
        final pattern = '%$trimmedQuery%';
        whereClauses.add(
          '(title LIKE ? OR authors LIKE ? OR isbn LIKE ? OR publisher LIKE ? '
          'OR categories LIKE ? OR original_title LIKE ? OR romaji_title LIKE ? OR original_author LIKE ?)',
        );
        whereArgs.addAll(List.filled(8, pattern));
      }

      final maps = await db.query(
        'books',
        where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
        whereArgs: whereArgs.isEmpty ? null : whereArgs,
        orderBy: orderBy,
      );
      return maps.map((m) => Book.fromMap(m)).toList();
    } catch (e) {
      throw StorageException('Nem sikerült betölteni a könyvtárat.', e);
    }
  }

  /// Get all books, ordered by date added (newest first).
  Future<List<Book>> getAllBooks({
    String orderBy = 'date_added DESC',
  }) {
    return queryBooks(orderBy: orderBy);
  }

  /// Get books filtered by reading status.
  Future<List<Book>> getBooksByStatus(
    String status, {
    String orderBy = 'date_added DESC',
  }) {
    return queryBooks(status: status, orderBy: orderBy);
  }

  /// Search books by title, author, or ISBN (case-insensitive partial match).
  Future<List<Book>> searchBooks(String query) {
    return queryBooks(searchQuery: query, orderBy: 'title ASC');
  }

  // ── Settings ──

  Future<String?> getSetting(String key) async {
    try {
      final db = await database;
      final rows = await db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: [key],
      );
      if (rows.isEmpty) return null;
      return rows.first['value'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> setSetting(String key, String value) async {
    try {
      final db = await database;
      await db.insert(
        'app_settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      throw StorageException('Nem sikerült elmenteni a beállítást.', e);
    }
  }

  // ── Statistics ──

  /// Get total count of books.
  Future<int> getTotalBookCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM books');
    return (result.first['count'] as num?)?.toInt() ?? 0;
  }

  /// Get count of books grouped by status.
  Future<Map<String, int>> getBookCountByStatus() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT status, COUNT(*) as count FROM books GROUP BY status',
    );
    final map = <String, int>{};
    for (final row in result) {
      map[row['status'] as String] = (row['count'] as num?)?.toInt() ?? 0;
    }
    return map;
  }

  /// Get average rating across all rated books.
  Future<double> getAverageRating() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT AVG(rating) as avg_rating FROM books WHERE rating IS NOT NULL AND rating > 0',
    );
    return (result.first['avg_rating'] as num?)?.toDouble() ?? 0.0;
  }

  /// Get total pages read across completed books and in-progress books.
  Future<int> getTotalPagesRead() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(
        CASE
          WHEN status IN ('completed', 'rereading') THEN COALESCE(page_count, current_page, 0)
          ELSE COALESCE(current_page, 0)
        END
      ), 0) as total_pages
      FROM books
    ''');
    return (result.first['total_pages'] as num?)?.toInt() ?? 0;
  }

  /// Get count of books finished in the current calendar year.
  Future<int> getBooksCompletedThisYear() async {
    final db = await database;
    final now = DateTime.now();
    final startOfYear = DateTime(now.year, 1, 1).millisecondsSinceEpoch;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count
      FROM books
      WHERE status = 'completed'
        AND COALESCE(date_finished, date_added) >= ?
    ''', [startOfYear]);
    return (result.first['count'] as num?)?.toInt() ?? 0;
  }

  /// Get count of books added per month (last 12 months).
  Future<List<Map<String, dynamic>>> getBooksAddedPerMonth() async {
    final db = await database;
    final twelveMonthsAgo = DateTime.now()
        .subtract(const Duration(days: 365))
        .millisecondsSinceEpoch;
    return db.rawQuery('''
      SELECT 
        strftime('%Y-%m', date_added / 1000, 'unixepoch') as month,
        COUNT(*) as count
      FROM books
      WHERE date_added >= ?
      GROUP BY month
      ORDER BY month ASC
    ''', [twelveMonthsAgo]);
  }

  /// Close the database.
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}

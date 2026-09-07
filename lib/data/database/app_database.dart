import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/book.dart';

/// SQLite database helper for the FreeLib app.
///
/// Uses raw sqflite instead of Drift to keep things simple and avoid
/// code generation complexity. Provides full CRUD + filtering + search.
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
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'freelib.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
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
        categories TEXT,
        cover_url TEXT,
        rating REAL,
        status TEXT NOT NULL DEFAULT 'planToRead',
        date_added INTEGER NOT NULL,
        date_started INTEGER,
        date_finished INTEGER,
        notes TEXT
      )
    ''');

    // Index for fast status filtering and search
    await db.execute('CREATE INDEX idx_books_status ON books (status)');
    await db.execute('CREATE INDEX idx_books_title ON books (title)');
    await db.execute('CREATE INDEX idx_books_isbn ON books (isbn)');
  }

  // ── CRUD Operations ──

  /// Insert a new book. Returns the row id.
  Future<int> insertBook(Book book) async {
    final db = await database;
    return db.insert(
      'books',
      book.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Update an existing book. Returns number of rows affected.
  Future<int> updateBook(Book book) async {
    final db = await database;
    return db.update(
      'books',
      book.toMap(),
      where: 'id = ?',
      whereArgs: [book.id],
    );
  }

  /// Delete a book by id. Returns number of rows affected.
  Future<int> deleteBook(int id) async {
    final db = await database;
    return db.delete(
      'books',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get a single book by id.
  Future<Book?> getBook(int id) async {
    final db = await database;
    final maps = await db.query(
      'books',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Book.fromMap(maps.first);
  }

  /// Get a single book by ISBN.
  Future<Book?> getBookByIsbn(String isbn) async {
    final db = await database;
    final maps = await db.query(
      'books',
      where: 'isbn = ?',
      whereArgs: [isbn],
    );
    if (maps.isEmpty) return null;
    return Book.fromMap(maps.first);
  }

  // ── Query Operations ──

  /// Get all books, ordered by date added (newest first).
  Future<List<Book>> getAllBooks({
    String orderBy = 'date_added DESC',
  }) async {
    final db = await database;
    final maps = await db.query('books', orderBy: orderBy);
    return maps.map((m) => Book.fromMap(m)).toList();
  }

  /// Get books filtered by reading status.
  Future<List<Book>> getBooksByStatus(
    String status, {
    String orderBy = 'date_added DESC',
  }) async {
    final db = await database;
    final maps = await db.query(
      'books',
      where: 'status = ?',
      whereArgs: [status],
      orderBy: orderBy,
    );
    return maps.map((m) => Book.fromMap(m)).toList();
  }

  /// Search books by title or author (case-insensitive partial match).
  Future<List<Book>> searchBooks(String query) async {
    final db = await database;
    final maps = await db.query(
      'books',
      where: 'title LIKE ? OR authors LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'title ASC',
    );
    return maps.map((m) => Book.fromMap(m)).toList();
  }

  // ── Statistics ──

  /// Get total count of books.
  Future<int> getTotalBookCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM books');
    return (result.first['count'] as int?) ?? 0;
  }

  /// Get count of books grouped by status.
  Future<Map<String, int>> getBookCountByStatus() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT status, COUNT(*) as count FROM books GROUP BY status',
    );
    final map = <String, int>{};
    for (final row in result) {
      map[row['status'] as String] = (row['count'] as int?) ?? 0;
    }
    return map;
  }

  /// Get average rating across all rated books.
  Future<double> getAverageRating() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT AVG(rating) as avg_rating FROM books WHERE rating IS NOT NULL AND rating > 0',
    );
    return (result.first['avg_rating'] as double?) ?? 0.0;
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

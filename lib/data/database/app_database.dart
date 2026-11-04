import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/book.dart';
import '../services/app_exceptions.dart';
import '../services/isbn_validator.dart';
import '../services/library_encryption_service.dart';

/// SQLite adatbázis-kezelő segédosztály a FreeLib alkalmazáshoz.
///
/// A felhasználó könyvtárát az alkalmazás zárt, elszigetelt belső tárhelyén tárolja
/// 256 bites ChaCha20 mezőszintű titkosítással, így külső alkalmazások nem tudják
/// elolvasni vagy gyorsítótárazni az adatokat.
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
      await LibraryEncryptionService.instance.init();

      final dir = await getApplicationDocumentsDirectory();
      // .nomedia fájl létrehozása a privát könyvtárban, hogy más appok / média-olvasók ne indexeljék
      final noMedia = File(p.join(dir.path, '.nomedia'));
      if (!await noMedia.exists()) {
        await noMedia.writeAsString('', flush: true);
      }

      final path = p.join(dir.path, 'freelib.db');
      final db = await openDatabase(
        path,
        version: 4,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );

      // Ha voltak korábban beszkennelt, még titkosítatlan könyvek, automatikusan titkosítjuk őket helyben
      await _encryptLegacyPlaintextRows(db);
      return db;
    } catch (e) {
      throw StorageException(
        'Nem sikerült megnyitni a helyi titkosított adatbázist.',
        e,
      );
    }
  }

  /// Automatikusan titkosítja a korábbi verziókból származó, még nyílt szövegű könyvsorokat,
  /// így a már beszkennelt könyvek adatvesztés nélkül átkerülnek a titkosított formátumba.
  Future<void> _encryptLegacyPlaintextRows(Database db) async {
    try {
      final rows = await db.query('books');
      final crypto = LibraryEncryptionService.instance;
      for (final row in rows) {
        final title = row['title'] as String?;
        if (title != null && !crypto.isEncryptedValue(title)) {
          final id = row['id'];
          final encryptedRow = crypto.encryptBookMap(row);
          await db.update(
            'books',
            encryptedRow,
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    } catch (_) {
      // Nem blokkoljuk az indulást, ha a migráció részlegesen már megtörtént
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

    await db.execute('CREATE INDEX idx_books_status ON books (status)');
    await db.execute('CREATE INDEX idx_books_title ON books (title)');
    await db.execute('CREATE INDEX idx_books_isbn ON books (isbn)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE books ADD COLUMN external_rating REAL');
      await db.execute(
          'ALTER TABLE books ADD COLUMN external_rating_count INTEGER');
      await db.execute(
          'ALTER TABLE books ADD COLUMN external_rating_source TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE books ADD COLUMN original_title TEXT');
      await db.execute('ALTER TABLE books ADD COLUMN romaji_title TEXT');
      await db.execute('ALTER TABLE books ADD COLUMN original_author TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE books ADD COLUMN current_page INTEGER');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
  }

  Book _decryptRow(Map<String, dynamic> row) {
    final decrypted = LibraryEncryptionService.instance.decryptBookMap(row);
    return Book.fromMap(decrypted);
  }

  // ── CRUD műveletek (Létrehozás, Olvasás, Frissítés, Törlés) ──

  /// Új könyv beszúrása titkosított formában. Visszaadja az új sor azonosítóját.
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
      final encryptedMap =
          LibraryEncryptionService.instance.encryptBookMap(book.toMap());
      return await db.insert(
        'books',
        encryptedMap,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } on AppException {
      rethrow;
    } catch (e) {
      throw StorageException('Nem sikerült elmenteni a könyvet.', e);
    }
  }

  /// Meglévő könyv frissítése titkosított formában. Visszaadja az érintett sorok számát.
  Future<int> updateBook(Book book) async {
    if (book.id == null) {
      throw const StorageException('A frissítendő könyvnek nincs azonosítója.');
    }
    try {
      final db = await database;
      final encryptedMap =
          LibraryEncryptionService.instance.encryptBookMap(book.toMap());
      return await db.update(
        'books',
        encryptedMap,
        where: 'id = ?',
        whereArgs: [book.id],
      );
    } catch (e) {
      throw StorageException('Nem sikerült frissíteni a könyv adatait.', e);
    }
  }

  /// Könyv törlése azonosító alapján. Visszaadja az érintett sorok számát.
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

  /// Egyetlen könyv lekérése azonosító alapján.
  Future<Book?> getBook(int id) async {
    try {
      final db = await database;
      final maps = await db.query(
        'books',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (maps.isEmpty) return null;
      return _decryptRow(maps.first);
    } catch (e) {
      throw StorageException('Nem sikerült lekérdezni a könyvet.', e);
    }
  }

  /// Egyetlen könyv lekérése ISBN alapján (ISBN-10 és ISBN-13 változatokat is ellenőrizve).
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
      return _decryptRow(maps.first);
    } catch (e) {
      throw StorageException('Nem sikerült ellenőrizni az ISBN-t.', e);
    }
  }

  // ── Lekérdezési műveletek ──

  /// Egységes lekérdezés, amely támogatja a kombinált szöveges keresést, állapot-szűrést
  /// és rendezést a memóriában visszafejtett könyveken, miközben a háttértáron minden titkosítva marad.
  Future<List<Book>> queryBooks({
    String? searchQuery,
    String? status,
    String orderBy = 'date_added DESC',
  }) async {
    try {
      final db = await database;
      final maps = await db.query(
        'books',
        where: (status != null && status.isNotEmpty) ? 'status = ?' : null,
        whereArgs: (status != null && status.isNotEmpty) ? [status] : null,
      );

      var books = maps.map(_decryptRow).toList();

      final trimmedQuery = searchQuery?.trim().toLowerCase() ?? '';
      if (trimmedQuery.isNotEmpty) {
        books = books.where((b) {
          return b.title.toLowerCase().contains(trimmedQuery) ||
              (b.authors?.toLowerCase().contains(trimmedQuery) ?? false) ||
              b.isbn.toLowerCase().contains(trimmedQuery) ||
              (b.publisher?.toLowerCase().contains(trimmedQuery) ?? false) ||
              (b.categories?.toLowerCase().contains(trimmedQuery) ?? false) ||
              (b.originalTitle?.toLowerCase().contains(trimmedQuery) ??
                  false) ||
              (b.romajiTitle?.toLowerCase().contains(trimmedQuery) ?? false) ||
              (b.originalAuthor?.toLowerCase().contains(trimmedQuery) ?? false);
        }).toList();
      }

      _sortBooksInMemory(books, orderBy);
      return books;
    } catch (e) {
      throw StorageException('Nem sikerült betölteni a könyvtárat.', e);
    }
  }

  void _sortBooksInMemory(List<Book> books, String orderBy) {
    final normalized = orderBy.toLowerCase();
    if (normalized.contains('date_added asc')) {
      books.sort((a, b) => a.dateAdded.compareTo(b.dateAdded));
    } else if (normalized.contains('title') && normalized.contains('desc')) {
      books.sort(
        (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
      );
    } else if (normalized.contains('title')) {
      books.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    } else if (normalized.contains('rating') && normalized.contains('desc')) {
      books.sort((a, b) {
        final rA = (a.rating != null && a.rating! > 0) ? a.rating! : -1.0;
        final rB = (b.rating != null && b.rating! > 0) ? b.rating! : -1.0;
        return rB.compareTo(rA);
      });
    } else if (normalized.contains('rating') && normalized.contains('asc')) {
      books.sort((a, b) {
        final rA = (a.rating != null && a.rating! > 0) ? a.rating! : 999.0;
        final rB = (b.rating != null && b.rating! > 0) ? b.rating! : 999.0;
        return rA.compareTo(rB);
      });
    } else {
      // Alapértelmezett rendezés: hozzáadás dátuma szerint csökkenő (date_added DESC)
      books.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    }
  }

  Future<List<Book>> getAllBooks({
    String orderBy = 'date_added DESC',
  }) {
    return queryBooks(orderBy: orderBy);
  }

  Future<List<Book>> getBooksByStatus(
    String status, {
    String orderBy = 'date_added DESC',
  }) {
    return queryBooks(status: status, orderBy: orderBy);
  }

  Future<List<Book>> searchBooks(String query) {
    return queryBooks(searchQuery: query, orderBy: 'title ASC');
  }

  // ── Alkalmazás-beállítások (szintén titkosítva a háttértáron) ──

  Future<String?> getSetting(String key) async {
    try {
      final db = await database;
      final rows = await db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: [key],
      );
      if (rows.isEmpty) return null;
      final rawVal = rows.first['value'] as String?;
      return LibraryEncryptionService.instance.decryptField(rawVal);
    } catch (_) {
      return null;
    }
  }

  Future<void> setSetting(String key, String value) async {
    try {
      final db = await database;
      final encryptedVal =
          LibraryEncryptionService.instance.encryptField(value) ?? value;
      await db.insert(
        'app_settings',
        {'key': key, 'value': encryptedVal},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      throw StorageException('Nem sikerült elmenteni a beállítást.', e);
    }
  }

  // ── Statisztikai lekérdezések ──

  Future<int> getTotalBookCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM books');
    return (result.first['count'] as num?)?.toInt() ?? 0;
  }

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

  Future<double> getAverageRating() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT AVG(rating) as avg_rating FROM books WHERE rating IS NOT NULL AND rating > 0',
    );
    return (result.first['avg_rating'] as num?)?.toDouble() ?? 0.0;
  }

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

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}

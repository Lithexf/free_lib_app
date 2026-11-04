import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_lib_app/data/models/book.dart';
import 'package:free_lib_app/data/models/reading_status.dart';
import 'package:free_lib_app/data/services/app_exceptions.dart';
import 'package:free_lib_app/data/services/book_api_service.dart';
import 'package:free_lib_app/data/services/isbn_validator.dart';
import 'package:free_lib_app/data/services/library_encryption_service.dart';
import 'package:free_lib_app/providers/book_providers.dart';
import 'package:free_lib_app/ui/screens/book_detail_screen.dart';
import 'package:free_lib_app/ui/screens/home_screen.dart';
import 'package:free_lib_app/ui/theme/app_colors.dart';
import 'package:free_lib_app/ui/theme/app_theme.dart';
import 'package:free_lib_app/ui/widgets/book_card.dart';
import 'package:free_lib_app/ui/widgets/scan_overlay.dart';
import 'package:free_lib_app/ui/widgets/status_badge.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Minimális memóriabeli Dio adapter az izolált API szolgáltatás tesztekhez.
class _FakeHttpAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;

  _FakeHttpAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class _FakeBookListNotifier extends BookListNotifier {
  final List<Book> initialBooks;
  _FakeBookListNotifier(this.initialBooks);

  @override
  Future<List<Book>> build() async => initialBooks;

  @override
  Future<Book> updateBook(Book book) async {
    state = AsyncData([
      for (final b in (state.valueOrNull ?? initialBooks))
        if (b.id == book.id) book else b,
    ]);
    return book;
  }

  @override
  Future<Book> addBook(Book book) async {
    final created = book.copyWith(id: 99);
    state = AsyncData([...(state.valueOrNull ?? initialBooks), created]);
    return created;
  }

  @override
  Future<void> deleteBook(int id) async {
    state = AsyncData([
      for (final b in (state.valueOrNull ?? initialBooks))
        if (b.id != id) b,
    ]);
  }
}

class _FakeYearlyGoalNotifier extends YearlyGoalNotifier {
  @override
  Future<int> build() async => 12;

  @override
  Future<void> updateGoal(int newGoal) async {
    state = AsyncData(newGoal);
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('hu');
  });

  group('IsbnValidator', () {
    test('validates ISBN-10 and ISBN-13 checksums accurately', () {
      expect(IsbnValidator.isValid('0-14-028329-3'), isTrue);
      expect(IsbnValidator.isValid('043942089X'), isTrue); // 'X' ellenőrző karakter
      expect(IsbnValidator.isValid('978-0-14-028329-7'), isTrue);
      expect(IsbnValidator.isValid('1234567890'), isFalse);
      expect(IsbnValidator.isValid('12345'), isFalse);
      expect(IsbnValidator.isValid('014028329A'), isFalse);
    });

    test('converts seamlessly between ISBN-10 and ISBN-13 and gets all formats', () {
      expect(IsbnValidator.isbn10to13('0140283293'), '9780140283297');
      expect(IsbnValidator.isbn10to13('invalid'), isNull);
      expect(IsbnValidator.isbn13to10('9780140283297'), '0140283293');
      expect(IsbnValidator.isbn13to10('123'), isNull);
      // A 979-es előtagnak nincs ISBN-10 megfelelője
      expect(IsbnValidator.isbn13to10('9791032700891'), isNull);

      final formats10 = IsbnValidator.getAllFormats('0140283293');
      expect(formats10, containsAll(['0140283293', '9780140283297']));

      final formats13 = IsbnValidator.getAllFormats('9780140283297');
      expect(formats13, containsAll(['9780140283297', '0140283293']));

      expect(IsbnValidator.isLikelyBookBarcode('9780140283290'), isTrue);
      expect(IsbnValidator.isLikelyBookBarcode('9791032700899'), isTrue);
      expect(IsbnValidator.isLikelyBookBarcode('0140283299'), isTrue);
      expect(IsbnValidator.isLikelyBookBarcode('5991234567890'), isFalse);
      expect(IsbnValidator.normalize('9780140283290'), '9780140283290');
      expect(IsbnValidator.normalize('5991234567890'), isNull);
    });
  });

  group('Book model, ReadingStatus & AppExceptions', () {
    test('handles int/double rating casting, copyWith, equality and toMap', () {
      final nowMs = DateTime(2026, 5, 10).millisecondsSinceEpoch;
      final book = Book.fromMap({
        'id': 7,
        'isbn': '9780140283297',
        'title': 'Egri csillagok',
        'subtitle': 'Történelmi regény',
        'authors': 'Gárdonyi Géza',
        'publisher': 'Móra',
        'published_date': '1901',
        'description': 'Leírás',
        'page_count': 520,
        'current_page': 260,
        'categories': 'Regény',
        'cover_url': 'https://example.com/cover.jpg',
        'rating': 5, // SQLite egész számos (integer) ábrázolás
        'status': 'reading',
        'date_added': nowMs,
        'date_started': nowMs,
        'date_finished': nowMs,
        'notes': 'Eredeti jegyzet',
        'original_title': 'Eredeti cím',
        'romaji_title': 'Romaji cím',
        'original_author': 'Eredeti szerző',
        'external_rating': 4.7,
        'external_rating_count': 120,
        'external_rating_source': 'Moly.hu',
      });

      expect(book.rating, 5.0);
      expect(book.readingProgress, closeTo(0.5, 0.001));
      expect(book.isManualIsbn, isFalse);
      expect(book.toString(), contains('Egri csillagok'));

      final completedBook = book.copyWith(status: 'completed');
      expect(completedBook.readingProgress, 1.0);

      final unstartedBook = book.copyWith(currentPage: 0);
      expect(unstartedBook.readingProgress, 0.0);

      // Opcionális mezők törlése a copyWith(notes: null, rating: null) hívással
      final cleared = book.copyWith(
        notes: null,
        rating: null,
        subtitle: null,
        pageCount: null,
      );
      expect(cleared.notes, isNull);
      expect(cleared.rating, isNull);
      expect(cleared.readingProgress, isNull);
      expect(cleared.title, 'Egri csillagok');
      expect(cleared, equals(book));
      expect(cleared.hashCode, equals(book.hashCode));
    });

    test('ReadingStatus, BookSortOrder and AppExceptions format properly', () {
      for (final status in ReadingStatus.values) {
        expect(ReadingStatus.fromString(status.name), status);
        expect(status.label, isNotEmpty);
      }
      expect(ReadingStatus.fromString('unknown_status'), ReadingStatus.planToRead);

      for (final sort in BookSortOrder.values) {
        expect(sort.label, isNotEmpty);
        expect(sort.sqlOrderBy, isNotEmpty);
      }

      final netEx = const NetworkException();
      final apiEx = const ApiLookupException();
      final dupEx = DuplicateBookException(isbn: '123', existingTitle: 'Teszt');
      final storEx = const StorageException();
      expect(netEx.toString(), contains('Hálózati hiba'));
      expect(apiEx.toString(), contains('külső könyvadatbázis'));
      expect(dupEx.toString(), contains('Teszt'));
      expect(storEx.toString(), contains('Adatbázis hiba'));
      expect(AppColors.primary, isNotNull);
    });

    test('encrypts book fields at rest and preserves legacy scanned books', () {
      final crypto = LibraryEncryptionService.instance;
      crypto.initWithTestKey(Uint8List.fromList(List.generate(32, (i) => i + 1)));

      final book = Book(
        id: 1,
        isbn: '9789631196009',
        title: 'Titkos Napló',
        authors: 'Teszt Szerző',
        notes: 'Privát személyes jegyzet',
        dateAdded: DateTime(2026, 4, 1),
      );

      final encryptedMap = crypto.encryptBookMap(book.toMap());
      expect(encryptedMap['title'], startsWith('ENC1:'));
      expect(crypto.isEncryptedValue(encryptedMap['title'] as String), isTrue);
      expect(encryptedMap['title'], isNot(contains('Titkos Napló')));
      expect(encryptedMap['notes'], startsWith('ENC1:'));
      expect(encryptedMap['notes'], isNot(contains('Privát')));

      // Oda-vissza titkosítás és visszafejtés után pontosan az eredeti könyvet kapjuk
      final decryptedMap = crypto.decryptBookMap(encryptedMap);
      final restored = Book.fromMap(decryptedMap);
      expect(restored.title, 'Titkos Napló');
      expect(restored.authors, 'Teszt Szerző');
      expect(restored.notes, 'Privát személyes jegyzet');

      // A korábbi nyílt szövegű sorok (már beszkennelt könyvek) továbbra is olvashatók maradnak
      final legacyDecrypted = crypto.decryptBookMap(book.toMap());
      expect(legacyDecrypted['title'], 'Titkos Napló');
    });
  });

  group('BookApiService error handling, parsing & translation', () {
    test('parses Google Books volume metadata and community ratings', () async {
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpAdapter((options) {
          final payload = jsonEncode({
            'totalItems': 1,
            'items': [
              {
                'id': 'vol1',
                'volumeInfo': {
                  'title': 'A Pál utcai fiúk',
                  'subtitle': 'Regény',
                  'authors': ['Molnár Ferenc'],
                  'publisher': 'Móra',
                  'publishedDate': '1907',
                  'description': 'Klasszikus ifjúsági regény',
                  'pageCount': 210,
                  'categories': ['Ifjúsági'],
                  'averageRating': 4.8,
                  'ratingsCount': 1240,
                  'imageLinks': {
                    'thumbnail': 'http://example.com/thumb.jpg',
                  },
                },
              }
            ],
          });
          return ResponseBody.fromString(
            payload,
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json; charset=utf-8'],
            },
          );
        });

      final service = BookApiService(dio: dio);
      final result = await service.lookupByIsbn('9780140283297');

      expect(result, isNotNull);
      expect(result!.title, 'A Pál utcai fiúk');
      expect(result.authors, 'Molnár Ferenc');
      expect(result.pageCount, 210);
      expect(result.coverUrl, 'https://example.com/thumb.jpg');
      expect(result.externalRating, 4.8);
      expect(result.externalRatingSource, 'Google Books');
    });

    test('parses Open Library batch details and search results with Japanese translation', () async {
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpAdapter((options) {
          if (options.uri.host.contains('googleapis.com') &&
              options.uri.path.contains('/volumes')) {
            return ResponseBody.fromString(
              jsonEncode({'totalItems': 0}),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json; charset=utf-8'],
              },
            );
          }

          if (options.uri.path.contains('/api/books')) {
            return ResponseBody.fromString(
              jsonEncode({
                'ISBN:9780140283297': {
                  'thumbnail_url': 'https://covers.openlibrary.org/b/id/123-S.jpg',
                  'details': {
                    'title': '進撃の巨人',
                    'authors': [
                      {'name': '諫山創'}
                    ],
                    'publishers': ['Kodansha'],
                    'publish_date': '2009',
                    'number_of_pages': 192,
                    'description': {'value': 'Manga leírás'},
                    'subjects': ['Manga', 'Action'],
                    'works': [
                      {'key': '/works/OL1W'}
                    ],
                  }
                }
              }),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json; charset=utf-8'],
              },
            );
          }

          if (options.uri.path.contains('/ratings.json')) {
            return ResponseBody.fromString(
              jsonEncode({
                'summary': {'average': 4.6, 'count': 350}
              }),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json; charset=utf-8'],
              },
            );
          }

          if (options.uri.path.contains('/search/authors.json')) {
            return ResponseBody.fromString(
              jsonEncode({
                'docs': [
                  {
                    'alternate_names': ['Hajime Isayama']
                  }
                ]
              }),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json; charset=utf-8'],
              },
            );
          }

          if (options.uri.path.contains('/search.json')) {
            return ResponseBody.fromString(
              jsonEncode({
                'numFound': 1,
                'docs': [
                  {
                    'key': '/works/OL1W',
                    'title': 'Attack on Titan',
                    'alternative_title': ['Attack on Titan'],
                    'author_name': ['Hajime Isayama'],
                    'publisher': ['Kodansha'],
                    'publish_date': ['2009'],
                    'number_of_pages_median': 192,
                    'subject': ['Manga'],
                    'cover_i': 12345,
                    'isbn': ['9780140283297'],
                    'ratings_average': 4.7,
                    'ratings_count': 500,
                  }
                ]
              }),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json; charset=utf-8'],
              },
            );
          }

          if (options.uri.host.contains('translate.googleapis.com')) {
            return ResponseBody.fromString(
              jsonEncode([
                [
                  ['Attack on Titan', '進撃の巨人', null, null],
                  [null, null, null, 'Shingeki no Kyojin']
                ]
              ]),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json; charset=utf-8'],
              },
            );
          }

          return ResponseBody.fromString('{}', 404);
        });

      final service = BookApiService(dio: dio);
      final book = await service.lookupByIsbn('9780140283297');
      expect(book, isNotNull);
      expect(book!.title, 'Attack on Titan');
      expect(book.romajiTitle, 'Shingeki No Kyojin');
      expect(book.authors, 'Hajime Isayama');
      expect(book.externalRating, 4.6);

      final searchResults = await service.searchBooksOnline('Attack on Titan');
      expect(searchResults, isNotEmpty);
      expect(searchResults.first.title, 'Attack on Titan');
    });

    test(
        'queries English APIs first and only falls back to Moly.hu last if English APIs return empty',
        () async {
      final calledHosts = <String>[];

      final dio = Dio()
        ..httpClientAdapter = _FakeHttpAdapter((options) {
          calledHosts.add('${options.uri.host}${options.uri.path}');

          // 1. A Google Books 0 találatot ad vissza
          if (options.uri.host.contains('googleapis.com')) {
            return ResponseBody.fromString(
              jsonEncode({'totalItems': 0}),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json; charset=utf-8'],
              },
            );
          }

          // 2. Az Open Library közvetlen API üres objektumot ad vissza
          if (options.uri.path.contains('/api/books')) {
            return ResponseBody.fromString(
              jsonEncode({}),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json; charset=utf-8'],
              },
            );
          }

          // 3. Az Open Library Search API 0 találatot ad vissza
          if (options.uri.path.contains('/search.json')) {
            return ResponseBody.fromString(
              jsonEncode({'numFound': 0, 'docs': []}),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json; charset=utf-8'],
              },
            );
          }

          // 4. A Moly.hu tartalék magyar könyv HTML-t ad vissza
          if (options.uri.host.contains('moly.hu')) {
            return ResponseBody.fromString(
              '<html><head><title>Gárdonyi Géza: Egri csillagok · Moly</title></head>'
              '<body><span>92%</span></body></html>',
              200,
              headers: {
                Headers.contentTypeHeader: ['text/html; charset=utf-8'],
              },
            );
          }

          return ResponseBody.fromString('{}', 404);
        });

      final service = BookApiService(dio: dio);
      final book = await service.lookupByIsbn('9789631196009');

      expect(book, isNotNull);
      expect(book!.title, 'Egri csillagok');
      expect(book.authors, 'Gárdonyi Géza');
      expect(book.externalRatingSource, 'Moly.hu');

      // Ellenőrizzük, hogy az angol API-k a moly.hu ELŐTT lettek lekérdezve
      final googleIndex =
          calledHosts.indexWhere((h) => h.contains('googleapis.com'));
      final openLibDirectIndex =
          calledHosts.indexWhere((h) => h.contains('openlibrary.org/api/books'));
      final openLibSearchIndex = calledHosts
          .indexWhere((h) => h.contains('openlibrary.org/search.json'));
      final molyIndex = calledHosts.indexWhere((h) => h.contains('moly.hu'));

      expect(googleIndex, greaterThanOrEqualTo(0));
      expect(openLibDirectIndex, greaterThan(googleIndex));
      expect(openLibSearchIndex, greaterThan(openLibDirectIndex));
      expect(molyIndex, greaterThan(openLibSearchIndex));
      expect(molyIndex, equals(calledHosts.length - 1));
    });

    test('throws NetworkException when device is offline', () async {
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpAdapter((options) {
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'No internet connection',
          );
        });

      final service = BookApiService(dio: dio);
      expect(
        () => service.lookupByIsbn('9780140283297'),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  group('Responsive UI, BookDetailScreen & Widgets', () {
    Widget buildTestApp({required Size size, List<Book> books = const []}) {
      return ProviderScope(
        overrides: [
          bookListProvider.overrideWith(() => _FakeBookListNotifier(books)),
          yearlyGoalProvider.overrideWith(_FakeYearlyGoalNotifier.new),
          bookStatsProvider.overrideWith((ref) async {
            return BookStats(
              totalCount: books.length,
              countByStatus: {
                for (final b in books) b.status: 1,
              },
              averageRating: 4.5,
              totalPagesRead: 320,
              completedThisYear: 1,
              yearlyGoal: 12,
              booksAddedPerMonth: const [
                {'month': '2026-04', 'count': 2},
                {'month': '2026-05', 'count': 4},
              ],
            );
          }),
        ],
        child: MediaQuery(
          data: MediaQueryData(size: size),
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const HomeScreen(),
          ),
        ),
      );
    }

    testWidgets(
        'uses BottomNavigationBar on compact mobile screens and navigates tabs',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildTestApp(size: const Size(390, 844)));
      await tester.pumpAndSettle();

      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('A könyvtárad üres'), findsOneWidget);

      // Navigálás a Hozzáadás fülre és Kézi felvétel űrlap ellenőrzése
      await tester.tap(find.text('Hozzáadás'));
      await tester.pumpAndSettle();
      expect(find.text('Könyv hozzáadása'), findsOneWidget);

      await tester.tap(find.text('Kézi felvétel'));
      await tester.pumpAndSettle();
      expect(find.text('Cím *'), findsOneWidget);

      // Navigálás a Statisztika fülre
      await tester.tap(find.text('Statisztika'));
      await tester.pumpAndSettle();
      expect(find.textContaining('olvasási kihívás'), findsOneWidget);
    });

    testWidgets(
        'uses NavigationRail on wide screens, toggles list view, and opens BookDetailScreen',
        (tester) async {
      tester.view.physicalSize = const Size(960, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final sampleBooks = [
        Book(
          id: 1,
          isbn: '9780140283297',
          title: 'Dűne',
          subtitle: 'A sivatygó bolygó',
          authors: 'Frank Herbert',
          publisher: 'Gabo',
          publishedDate: '1965',
          description: 'Klasszikus sci-fi regény.',
          pageCount: 600,
          currentPage: 300,
          categories: 'Sci-Fi',
          status: 'reading',
          rating: 4.5,
          externalRating: 4.8,
          externalRatingSource: 'Google Books',
          dateAdded: DateTime(2026, 3, 1),
          dateStarted: DateTime(2026, 3, 2),
        ),
      ];

      await tester.pumpWidget(
        buildTestApp(size: const Size(960, 720), books: sampleBooks),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.text('Dűne'), findsWidgets);
      expect(find.text('Frank Herbert'), findsOneWidget);

      // Listanézetre váltás
      await tester.tap(find.byIcon(Icons.view_list));
      await tester.pumpAndSettle();
      expect(find.byType(BookCard), findsOneWidget);

      // Könyv adatlap megnyitása
      await tester.tap(find.text('Frank Herbert'));
      await tester.pumpAndSettle();
      expect(find.byType(BookDetailScreen), findsOneWidget);
      expect(find.text('Könyv adatlap'), findsOneWidget);
      expect(find.text('300 / 600 oldal (50%)'), findsOneWidget);

      // +10 oldal gomb megnyomása
      await tester.tap(find.text('+10 oldal'));
      await tester.pumpAndSettle();
      expect(find.text('310 / 600 oldal (52%)'), findsOneWidget);

      // Kész gomb megnyomása
      await tester.tap(find.text('Kész'));
      await tester.pumpAndSettle();
      expect(find.text('600 / 600 oldal (100%)'), findsOneWidget);
    });

    testWidgets('renders ScanOverlay and StatusBadge widgets cleanly',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: Column(
              children: [
                Expanded(child: ScanOverlay()),
                StatusBadge(status: ReadingStatus.reading, selected: true),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Tartsd a vonalkódot a keretbe'), findsOneWidget);
      expect(find.text('Olvasom'), findsOneWidget);
    });
  });
}

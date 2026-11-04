import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_lib_app/data/models/book.dart';
import 'package:free_lib_app/data/services/app_exceptions.dart';
import 'package:free_lib_app/data/services/book_api_service.dart';
import 'package:free_lib_app/data/services/isbn_validator.dart';
import 'package:free_lib_app/data/services/library_encryption_service.dart';
import 'package:free_lib_app/providers/book_providers.dart';
import 'package:free_lib_app/ui/screens/home_screen.dart';
import 'package:free_lib_app/ui/theme/app_theme.dart';

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
}

class _FakeYearlyGoalNotifier extends YearlyGoalNotifier {
  @override
  Future<int> build() async => 12;
}

void main() {
  group('IsbnValidator', () {
    test('validates ISBN-10 and ISBN-13 checksums accurately', () {
      expect(IsbnValidator.isValid('0-14-028329-3'), isTrue);
      expect(IsbnValidator.isValid('043942089X'), isTrue); // 'X' ellenőrző karakter
      expect(IsbnValidator.isValid('978-0-14-028329-7'), isTrue);
      expect(IsbnValidator.isValid('1234567890'), isFalse);
    });

    test('converts seamlessly between ISBN-10 and ISBN-13', () {
      expect(IsbnValidator.isbn10to13('0140283293'), '9780140283297');
      expect(IsbnValidator.isbn13to10('9780140283297'), '0140283293');
      // A 979-es előtagnak nincs ISBN-10 megfelelője
      expect(IsbnValidator.isbn13to10('9791032700891'), isNull);
    });
  });

  group('Book model', () {
    test('handles int/double rating casting and nullable copyWith clearing', () {
      final nowMs = DateTime(2026, 5, 10).millisecondsSinceEpoch;
      final book = Book.fromMap({
        'id': 7,
        'isbn': '9780140283297',
        'title': 'Egri csillagok',
        'authors': 'Gárdonyi Géza',
        'page_count': 520,
        'current_page': 260,
        'rating': 5, // SQLite egész számos (integer) ábrázolás
        'status': 'reading',
        'date_added': nowMs,
        'notes': 'Eredeti jegyzet',
      });

      expect(book.rating, 5.0);
      expect(book.readingProgress, closeTo(0.5, 0.001));

      // Opcionális mezők törlése a copyWith(notes: null, rating: null) hívással
      final cleared = book.copyWith(notes: null, rating: null);
      expect(cleared.notes, isNull);
      expect(cleared.rating, isNull);
      expect(cleared.title, 'Egri csillagok');
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

  group('BookApiService error handling & parsing', () {
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
                  'authors': ['Molnár Ferenc'],
                  'pageCount': 210,
                  'averageRating': 4.8,
                  'ratingsCount': 1240,
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
      expect(result.externalRating, 4.8);
      expect(result.externalRatingSource, 'Google Books');
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

  group('Responsive UI & Navigation', () {
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
              booksAddedPerMonth: const [],
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

      // Navigálás a Hozzáadás fülre
      await tester.tap(find.text('Hozzáadás'));
      await tester.pumpAndSettle();
      expect(find.text('Könyv hozzáadása'), findsOneWidget);

      // Navigálás a Statisztika fülre
      await tester.tap(find.text('Statisztika'));
      await tester.pumpAndSettle();
      expect(find.textContaining('olvasási kihívás'), findsOneWidget);
    });

    testWidgets('uses NavigationRail on wide tablet/landscape screens cleanly',
        (tester) async {
      tester.view.physicalSize = const Size(960, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final sampleBooks = [
        Book(
          id: 1,
          isbn: '9780140283297',
          title: 'Dűne',
          authors: 'Frank Herbert',
          pageCount: 600,
          currentPage: 300,
          status: 'reading',
          rating: 4.5,
          dateAdded: DateTime(2026, 3, 1),
        ),
      ];

      await tester.pumpWidget(
        buildTestApp(size: const Size(960, 640), books: sampleBooks),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.text('Dűne'), findsWidgets);
      expect(find.text('Frank Herbert'), findsOneWidget);
    });
  });
}

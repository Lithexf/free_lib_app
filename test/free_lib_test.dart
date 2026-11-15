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
    test('ISBN-10 es ISBN-13 ellenorzes', () {
      expect(IsbnValidator.isValid('0-14-028329-3'), isTrue);
      expect(IsbnValidator.isValid('043942089X'), isTrue);
      expect(IsbnValidator.isValid('978-0-14-028329-7'), isTrue);
      expect(IsbnValidator.isValid('1234567890'), isFalse);
      expect(IsbnValidator.isValid('12345'), isFalse);
      expect(IsbnValidator.isValid('014028329A'), isFalse);
    });

    test('ISBN-10 es ISBN-13 konverzio es formatumok', () {
      expect(IsbnValidator.isbn10to13('0140283293'), '9780140283297');
      expect(IsbnValidator.isbn10to13('invalid'), isNull);
      expect(IsbnValidator.isbn13to10('9780140283297'), '0140283293');
      expect(IsbnValidator.isbn13to10('123'), isNull);
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
      expect(IsbnValidator.isValid('123456789012X'), isFalse);
      expect(IsbnValidator.isbn10to13('123X567890'), isNull);
      expect(
        IsbnValidator.getAllFormats('LOCAL-GB-x123456789'),
        ['LOCAL-GB-x123456789'],
      );
    });

    test('Magyar ISBN es EAN kiegeszites kezeles', () {
      expect(IsbnValidator.isValid('9789634058397'), isTrue);
      expect(IsbnValidator.isHungarianIsbn('9789634058397'), isTrue);
      expect(IsbnValidator.isHungarianIsbn('978-615-5956-01-0'), isTrue);
      expect(IsbnValidator.isHungarianIsbn('9631196003'), isTrue);
      expect(IsbnValidator.isHungarianIsbn('9780140283297'), isFalse);
      expect(IsbnValidator.isHungarianIsbn('9781974700523'), isFalse);

      expect(IsbnValidator.normalize('978197470052350999'), '9781974700523');
      expect(IsbnValidator.isValid('978197470052350999'), isTrue);
      expect(IsbnValidator.isLikelyBookBarcode('978197470052350999'), isTrue);

      expect(IsbnValidator.normalize('043942089x'), '043942089X');
    });
  });

  group('Book modell es allapotok', () {
    test('Book szerializacio, copyWith es egyenloseg', () {
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
        'rating': 5,
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

    test('ReadingStatus, BookSortOrder es kivetelek', () {
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

    test('Konyv mezok titkositasa es visszaallitasa', () {
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

      final decryptedMap = crypto.decryptBookMap(encryptedMap);
      final restored = Book.fromMap(decryptedMap);
      expect(restored.title, 'Titkos Napló');
      expect(restored.authors, 'Teszt Szerző');
      expect(restored.notes, 'Privát személyes jegyzet');

      final legacyDecrypted = crypto.decryptBookMap(book.toMap());
      expect(legacyDecrypted['title'], 'Titkos Napló');
    });
  });

  group('BookApiService tesztek', () {
    test('Google Books metaadatok es ertekelesek', () async {
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

    test('Open Library adatok es japan cim forditas', () async {
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
        'Bookline magyar ISBN kereses (9789634058397)',
        () async {
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpAdapter((options) {
          if (options.uri.host.contains('googleapis.com')) {
            return ResponseBody.fromString(
              jsonEncode({'totalItems': 0}),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json; charset=utf-8'],
              },
            );
          }

          if (options.uri.host.contains('bookline.hu') &&
              options.uri.path.contains('/search/search.action')) {
            const searchHtml = '''
<div class="t-product-detailed">
  <img data-srcset="[https://marvin.bline.hu/product_images/223/ID22-298546.JPG, https://marvin.bline.hu/product_images/223/B1298546.JPG]"
       src="https://marvin.bline.hu/product_images/223/B1298546.JPG" />
  <a href="/product/home.action?_v=J_R_R_Tolkien_A_Gyuruk_Ura_I_III_&amp;type=22&amp;id=298546&amp;ca=SEARCH" class="o-product__author">
    J. R. R. Tolkien
  </a>
  <h2 class="o-product__title h4">
    <a href="/product/home.action?_v=J_R_R_Tolkien_A_Gyuruk_Ura_I_III_&amp;type=22&amp;id=298546&amp;ca=SEARCH" class="o-product__title">
      A Gyűrűk Ura I-III.
    </a>
  </h2>
  <div class="js-Raty o-raty" data-stars="4.5" data-favcount="15"></div>
  <p class="o-product__lead">A Gyűrűk Ura J. R. R. Tolkien világhírű fantasy-klasszikusa.</p>
  <div class="o-product__publisher">Európa Könyvkiadó, 2025</div>
</div>
''';
            return ResponseBody.fromString(
              searchHtml,
              200,
              headers: {
                Headers.contentTypeHeader: ['text/html; charset=utf-8'],
              },
            );
          }

          if (options.uri.host.contains('bookline.hu') &&
              options.uri.path.contains('/product/home.action')) {
            const detailHtml = '''
<html>
<head>
  <meta name="description" content="Kategória: Fantasy, Ár: 17099 Ft"/>
  <meta property="og:description" content="A Gyűrűk Ura J. R. R. Tolkien világhírű fantasy-klasszikusa most egyetlen kötetben olvasható."/>
</head>
<body>
  <span itemprop="sku">9789634058397</span>
  <ul>
    <li>Európa Könyvkiadó, 2025</li>
    <li>1774 oldal</li>
    <li>Eredeti cím: The Lord of the Rings</li>
  </ul>
</body>
</html>
''';
            return ResponseBody.fromString(
              detailHtml,
              200,
              headers: {
                Headers.contentTypeHeader: ['text/html; charset=utf-8'],
              },
            );
          }

          return ResponseBody.fromString('{}', 404);
        });

      final service = BookApiService(dio: dio);
      final book = await service.lookupByIsbn('9789634058397');

      expect(book, isNotNull);
      expect(book!.isbn, '9789634058397');
      expect(book.title, 'A Gyűrűk Ura I-III.');
      expect(book.authors, 'J. R. R. Tolkien');
      expect(book.publisher, 'Európa Könyvkiadó');
      expect(book.publishedDate, '2025');
      expect(book.pageCount, 1774);
      expect(book.categories, 'Fantasy');
      expect(book.originalTitle, 'The Lord of the Rings');
      expect(book.externalRating, 4.5);
      expect(book.externalRatingCount, 15);
      expect(book.externalRatingSource, 'Bookline');
      expect(
        book.coverUrl,
        'https://marvin.bline.hu/product_images/223/ID22-298546.JPG',
      );
    });

    test(
        'Angol manga kereses Open Library segitsegevel (9781974700523)',
        () async {
      int googleCalls = 0;

      final dio = Dio()
        ..httpClientAdapter = _FakeHttpAdapter((options) {
          if (options.uri.host.contains('googleapis.com')) {
            googleCalls++;
            return ResponseBody.fromString(
              jsonEncode({'error': 'Rate limit exceeded'}),
              429,
              headers: {
                Headers.contentTypeHeader: ['application/json; charset=utf-8'],
              },
            );
          }

          if (options.uri.path.contains('/api/books')) {
            return ResponseBody.fromString(
              jsonEncode({
                'ISBN:9781974700523': {
                  'thumbnail_url':
                      'https://covers.openlibrary.org/b/id/9157307-S.jpg',
                  'details': {
                    'title': 'Demon Slayer',
                    'subtitle': 'Kimetsu no Yaiba, Vol. 1',
                    'publishers': ['VIZ Media LLC'],
                    'publish_date': 'Jul 03, 2018',
                    'number_of_pages': 192,
                  }
                }
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
                    'key': '/works/OL20641122W',
                    'title': '鬼滅の刃 1',
                    'author_name': ['Koyoharu Gotoge'],
                    'publisher': ['VIZ Media LLC'],
                    'publish_date': ['2018'],
                    'number_of_pages_median': 192,
                    'subject': ['Manga', 'Fantasy', 'Shonen'],
                    'cover_i': 9157307,
                    'isbn': ['9781974700523'],
                    'ratings_average': 4.43,
                    'ratings_count': 70,
                  }
                ]
              }),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json; charset=utf-8'],
              },
            );
          }

          return ResponseBody.fromString('{}', 404);
        });

      final service = BookApiService(dio: dio);
      final book = await service.lookupByIsbn('978197470052350999');

      expect(book, isNotNull);
      expect(googleCalls, 1);
      expect(book!.title, 'Demon Slayer');
      expect(book.subtitle, 'Kimetsu no Yaiba, Vol. 1');
      expect(book.originalTitle, '鬼滅の刃 1');
      expect(book.authors, 'Koyoharu Gotoge');
      expect(book.publisher, 'VIZ Media LLC');
      expect(book.pageCount, 192);
      expect(book.categories, 'Manga, Fantasy, Shonen');
      expect(book.externalRating, closeTo(4.43, 0.01));
      expect(book.externalRatingSource, 'Open Library');
    });

    test(
        'Tartalek forrasok sorrendje',
        () async {
      final calledHosts = <String>[];

      final dio = Dio()
        ..httpClientAdapter = _FakeHttpAdapter((options) {
          calledHosts.add('${options.uri.host}${options.uri.path}');

          if (options.uri.host.contains('bookline.hu')) {
            return ResponseBody.fromString(
              '<html><body>nem találtunk a keresésnek megfelelő terméket</body></html>',
              200,
              headers: {
                Headers.contentTypeHeader: ['text/html; charset=utf-8'],
              },
            );
          }

          if (options.uri.host.contains('antikvarium.hu')) {
            return ResponseBody.fromString(
              '<div class="empty"></div>',
              200,
              headers: {
                Headers.contentTypeHeader: ['text/html; charset=utf-8'],
              },
            );
          }

          if (options.uri.host.contains('googleapis.com')) {
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
              jsonEncode({}),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json; charset=utf-8'],
              },
            );
          }

          if (options.uri.path.contains('/search.json')) {
            return ResponseBody.fromString(
              jsonEncode({'numFound': 0, 'docs': []}),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json; charset=utf-8'],
              },
            );
          }

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

      final molyIndex = calledHosts.indexWhere((h) => h.contains('moly.hu'));
      expect(molyIndex, equals(calledHosts.length - 1));
    });

    test('Halozati hiba kezelese offline allapotban', () async {
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

  group('Felhasznaloi felulet tesztek', () {
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
        'Mobil navigacio es menupontok',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildTestApp(size: const Size(390, 844)));
      await tester.pumpAndSettle();

      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('A könyvtárad üres'), findsOneWidget);

      await tester.tap(find.text('Hozzáadás'));
      await tester.pumpAndSettle();
      expect(find.text('Könyv hozzáadása'), findsOneWidget);

      await tester.tap(find.text('Kézi felvétel'));
      await tester.pumpAndSettle();
      expect(find.text('Cím *'), findsOneWidget);

      await tester.tap(find.text('Statisztika'));
      await tester.pumpAndSettle();
      expect(find.textContaining('olvasási kihívás'), findsOneWidget);
    });

    testWidgets(
        'Szeles kepernyos nezet, listanezet es adatlap',
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

      await tester.tap(find.byIcon(Icons.view_list));
      await tester.pumpAndSettle();
      expect(find.byType(BookCard), findsOneWidget);

      await tester.tap(find.text('Frank Herbert'));
      await tester.pumpAndSettle();
      expect(find.byType(BookDetailScreen), findsOneWidget);
      expect(find.text('Könyv adatlap'), findsOneWidget);
      expect(find.text('300 / 600 oldal (50%)'), findsOneWidget);

      await tester.tap(find.text('+10 oldal'));
      await tester.pumpAndSettle();
      expect(find.text('310 / 600 oldal (52%)'), findsOneWidget);

      await tester.tap(find.text('Kész'));
      await tester.pumpAndSettle();
      expect(find.text('600 / 600 oldal (100%)'), findsOneWidget);
    });

    testWidgets('ScanOverlay es StatusBadge megjelenites',
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

    testWidgets(
        'Konyv adatlap mentes gomb es ertesitesek kezelese',
        (tester) async {
      final scannedBook = Book(
        id: 1,
        isbn: '9780140283297',
        title: 'Újonnan szkennelt könyv',
        authors: 'Teszt Szerző',
        dateAdded: DateTime(2026, 5, 1),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bookListProvider
                .overrideWith(() => _FakeBookListNotifier([scannedBook])),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Már a könyvtárban van: Teszt'),
                        ),
                      );
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BookDetailScreen(
                            book: scannedBook,
                            isNewlyScanned: true,
                          ),
                        ),
                      );
                    },
                    child: const Text('Szkennelés szimuláció'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Szkennelés szimuláció'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Már a könyvtárban van'), findsNothing);

      final addBtnFinder =
          find.widgetWithText(ElevatedButton, 'Hozzáadás a könyvtárhoz');
      expect(addBtnFinder, findsOneWidget);
      final addBtn = tester.widget<ElevatedButton>(addBtnFinder);
      expect(addBtn.onPressed, isNotNull);

      await tester.ensureVisible(addBtnFinder);
      await tester.tap(addBtnFinder);
      await tester.pumpAndSettle();

      expect(find.text('Szkennelés szimuláció'), findsOneWidget);
    });

    testWidgets(
        '300 konyv betoltese, titkositasa es gorgetese',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final crypto = LibraryEncryptionService.instance;
      final statuses = ReadingStatus.values;

      final books300 = List<Book>.generate(300, (index) {
        final isbn = index % 10 == 0
            ? 'LOCAL-GB-x12345678$index'
            : '9780140${(100000 + index).toString()}';
        final rawBook = Book(
          id: index + 1,
          isbn: isbn,
          title: 'Teszt Könyv #${index + 1}: Hosszú Cím és Különleges Karakterek ÁÉÍÓÖŐÚÜŰ',
          subtitle: 'Alcím a(z) ${index + 1}. kötethez',
          authors: 'Szerző ${(index % 40) + 1}',
          publisher: 'Kiadó ${(index % 15) + 1}',
          publishedDate: '${1990 + (index % 35)}',
          description: 'Részletes leírás a könyvről ' * 8,
          pageCount: 150 + (index * 5),
          currentPage: (index * 2) % 150,
          categories: 'Regény, Klasszikus',
          status: statuses[index % statuses.length].name,
          rating: (index % 5 == 0) ? null : ((index % 5) + 1).toDouble(),
          dateAdded: DateTime(2026, (index % 12) + 1, (index % 28) + 1),
        );

        final encryptedMap = crypto.encryptBookMap(rawBook.toMap());
        final decryptedMap = crypto.decryptBookMap(encryptedMap);
        return Book.fromMap(decryptedMap);
      });

      expect(books300.length, 300);
      expect(books300.first.title, contains('Teszt Könyv #1'));
      expect(books300.last.pageCount, greaterThan(1500));

      await tester.pumpWidget(
        buildTestApp(size: const Size(390, 844), books: books300),
      );
      await tester.pumpAndSettle();

      expect(find.text('Összes könyv: 300'), findsOneWidget);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.view_list));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            bookListProvider
                .overrideWith(() => _FakeBookListNotifier(books300)),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: BookDetailScreen(book: books300.last),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsOneWidget);
    });
  });
}
# FreeLib

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![Language](https://img.shields.io/badge/language-Dart-blue)
![Flutter](https://img.shields.io/badge/Flutter-%2302569B?logo=flutter&logoColor=white)
![Összes sor](https://img.shields.io/badge/%C3%96sszes_sor-4850-blueviolet)

## Áttekintés

Mivel a [Libib](https://www.libib.com/) fizetős lett, a **FreeLib** egy ingyenes, adatvédelem-központú, offline is használható Flutter alkalmazás személyes könyvtár kezelésére. Könyveket, mangákat és képregényeket kamerás ISBN-vonalkód beolvasással, online cím/szerző kereséssel vagy manuális űrlapon lehet felvenni.

Az alkalmazás régió-alapú gyors keresési stratégiával (magyar ISBN-eknél Bookline.hu + Google Books + Antikvarium.hu, nemzetközi/manga ISBN-eknél Google Books + Open Library, végső tartalékként Moly.hu, kiegészítve automatikus japán–angol/romaji fordítóval) gyűjti be a könyv adatait és borítóját, majd a felhasználó könyvtárát helyi, 256 bites ChaCha20 algoritmussal titkosított SQLite-adatbázisban tárolja.

## Fő funkciók

- **Gyors kamerás vonalkódolvasó (képadat-izolációval)**: ML Kit alapú, azonnali EAN-13 / EAN-8 / UPC vonalkód-felismerés `returnImage: false` beállítással, így az alkalmazás soha nem látja vagy menti el a kameraképet és a galériát.
- **Többforrású ISBN azonosítás**: Gyors magyar (Bookline, Antikvarium) és nemzetközi (Google Books, Open Library) lekérdezés automatikus metaadat-összefésüléssel.
- **Titkosított helyi tárolás (256 bites ChaCha20 + MAC)**: A beszkennelt könyvek az alkalmazás elszigetelt belső tárhelyén, mezőszinten titkosítva (`ENC1:<base64>`) kerülnek mentésre (`allowBackup="false"`, `.nomedia` védelemmel).
- **Online katalóguskereső és kézi könyvfelvétel**: Keresés cím vagy szerző alapján vonalkód nélkül is, illetve űrlapos kézi hozzáadás és szerkesztés.
- **Olvasási haladás és állapotkövetés**: 6 olvasási állapot, oldalszám-csúszka és gyorsgombok, személyes 0.5–5.0 csillagos értékelés összevetve a közösségi átlaggal, valamint titkosított jegyzetelés.
- **Statisztika és éves olvasási kihívás**: Testreszabható éves olvasási cél követése, összes elolvasott oldalszám, állapotszerinti kördiagram és havi gyarapodási oszlopdiagram.
- **Letisztult sötét téma (Dark Mode)**: Egyszerű, animációmentes, átlátható felület reszponzív elrendezéssel (`BottomNavigationBar` mobilon, `NavigationRail` széles kijelzőn).

## Projektstruktúra

```text
free_lib_app/
├── android/
├── lib/
│   ├── main.dart
│   ├── data/
│   │   ├── database/
│   │   │   └── app_database.dart
│   │   ├── models/
│   │   │   ├── book.dart
│   │   │   └── reading_status.dart
│   │   └── services/
│   │       ├── app_exceptions.dart
│   │       ├── book_api_service.dart
│   │       ├── isbn_validator.dart
│   │       └── library_encryption_service.dart
│   ├── providers/
│   │   ├── book_providers.dart
│   │   └── database_provider.dart
│   └── ui/
│       ├── screens/
│       ├── theme/
│       └── widgets/
├── test/
│   └── free_lib_test.dart
├── icon.ico
├── pubspec.yaml
├── signature.yaml
└── FreeLib_latest.apk
```

## Futtatás, tesztelés és csomagolás

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

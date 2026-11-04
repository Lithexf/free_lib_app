# FreeLib

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![Language](https://img.shields.io/badge/language-Dart-blue)
![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?logo=Flutter&logoColor=white)

## Áttekintés

Mivel a [Libib](https://www.libib.com/) fizetős lett, a **FreeLib** egy ingyenes, adatvédelem-központú, offline is használható Flutter alkalmazás személyes könyvtár kezelésére. Könyveket, mangákat és képregényeket kamerás ISBN-vonalkód beolvasással, online cím/szerző kereséssel vagy manuális űrlapon lehet felvenni.

Az alkalmazás kétfázisú keresési stratégiával (először gyors angol/nemzetközi JSON API-k: Google Books és Open Library, majd végső tartalékként a magyar Moly.hu, kiegészítve automatikus japán–angol/romaji fordítóval) gyűjti be a könyv adatait és borítóját, majd a felhasználó könyvtárát helyi, 256 bites ChaCha20 algoritmussal titkosított SQLite-adatbázisban tárolja.

## Fő funkciók

- **Gyors kamerás vonalkódolvasó (képadat-izolációval)**: ML Kit alapú, azonnali EAN-13 / EAN-8 / UPC vonalkód-felismerés `returnImage: false` beállítással, így az alkalmazás soha nem látja vagy menti el a kameraképet és a galériát.
- **Kétfázisú, többforrású ISBN azonosítás**: Először a gyors angol/nemzetközi API-kban (Google Books, Open Library Direct és Search) keres, és csak találat hiányában kérdezi le a lassabb magyar Moly.hu oldalt.
- **Titkosított helyi tárolás (256 bites ChaCha20 + MAC)**: A beszkennelt könyvek az alkalmazás elszigetelt belső tárhelyén, mezőszinten titkosítva (`ENC1:<base64>`) kerülnek mentésre (`allowBackup="false"`, `.nomedia` védelemmel), így külső alkalmazások nem férhetnek hozzá és nem tudják gyorsítótárazni.
- **Online katalóguskereső és kézi könyvfelvétel**: Keresés cím vagy szerző alapján vonalkód nélkül is, illetve űrlapos kézi hozzáadás és szerkesztés.
- **Olvasási haladás és állapotkövetés**: 6 olvasási állapot, oldalszám-csúszka és gyorsgombok, személyes 0.5–5.0 csillagos értékelés összevetve a közösségi átlaggal, valamint titkosított jegyzetelés.
- **Statisztika és éves olvasási kihívás**: Testreszabható éves olvasási cél követése, összes elolvasott oldalszám, állapotszerinti kördiagram és havi gyarapodási oszlopdiagram.
- **Letisztult sötét téma (Dark Mode)**: Egyszerű, animációmentes, átlátható felület reszponzív elrendezéssel (`BottomNavigationBar` mobilon, `NavigationRail` széles kijelzőn).

## Projektstruktúra (Source Tree)

```text
free_lib_app/
├── android/                        # Android natív konfiguráció, Manifest és generált ikonok (mipmap-*)
├── assets/
│   └── icons/
│       └── icon.png                # Alkalmazás- és APK-ikon forrásfájl
├── lib/
│   ├── main.dart                   # Alkalmazás belépési pont és globális hibakezelés
│   ├── data/
│   │   ├── database/
│   │   │   └── app_database.dart   # SQLite adatbázis-kezelő és automatikus titkosítási migráció
│   │   ├── models/
│   │   │   ├── book.dart           # Könyv (Book) adatmodell
│   │   │   └── reading_status.dart # Olvasási állapotok (ReadingStatus)
│   │   └── services/
│   │       ├── app_exceptions.dart             # Strukturált kivételosztályok
│   │       ├── book_api_service.dart           # Kétfázisú ISBN és könyvkereső API szolgáltatás
│   │       ├── isbn_validator.dart             # ISBN-10 / ISBN-13 ellenőrző és konvertáló
│   │       └── library_encryption_service.dart # 256 bites ChaCha20 + MAC helyi titkosító
│   ├── providers/
│   │   ├── book_providers.dart     # Riverpod állapotkezelők (könyvlista, szűrők, statisztika)
│   │   └── database_provider.dart  # Adatbázis és API szolgáltatók
│   └── ui/
│       ├── screens/                # Képernyők (Főoldal, Hozzáadás, Szkenner, Adatlap, Statisztika)
│       ├── theme/                  # Egyszerű sötét téma (AppTheme) és színpaletta (AppColors)
│       └── widgets/                # Újrafelhasználható UI elemek (BookCard, EmptyState, stb.)
├── test/
│   └── free_lib_test.dart          # Egység- és felületi (widget) tesztek
├── pubspec.yaml                    # Függőségek, eszközök és ikon-generátor konfiguráció
└── FreeLib_latest.apk              # Telepíthető, aláírt kiadási (release) Android APK csomag
```

## Futtatás, tesztelés és csomagolás

```sh
flutter pub get
dart run flutter_launcher_icons
flutter analyze
flutter test
flutter build apk --release
```

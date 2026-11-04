# FreeLib

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![Language](https://img.shields.io/badge/language-Dart-blue)
![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?logo=Flutter&logoColor=white)

## Áttekintés

Mivel a [Libib](https://www.libib.com/) fizetős lett, a **FreeLib** egy ingyenes, adatvédelem-központú, offline is használható Flutter alkalmazás személyes könyvtár kezelésére. Könyveket, mangákat és képregényeket kamerás ISBN-vonalkód beolvasással, online cím/szerző kereséssel vagy teljesen manuális űrlapon lehet felvenni. Az alkalmazás többlépcsős stratégiával (Google Books, Open Library, Moly.hu, valamint automatikus japán–angol/romaji fordítóval) gyűjti be a könyv adatait és borítóját, majd helyi SQLite-adatbázisban tárolja.

## Fő funkciók

- **Többforrású ISBN azonosítás**: ISBN-13 és ISBN-10 ellenőrzés és keresés Google Books, Open Library és Moly.hu forrásokból, japán kiadások automatikus fordításával és átírásával (Romaji).
- **Kamerás vonalkódolvasó**: Valós idejű ML Kit alapú szkenner animált célzókerettel, zseblámpával, kameraváltással és kézi ISBN megadással.
- **Online katalóguskereső és kézi könyvfelvétel**: Keresés cím vagy szerző alapján vonalkód nélkül is, illetve űrlapos kézi hozzáadás és szerkesztés offline vagy ISBN nélküli kiadásokhoz.
- **Olvasási haladás és állapotkövetés**: 6 olvasási állapot, oldalszám-csúszka és gyorsgombok (`+10`, `+25` oldal), személyes 0.5–5.0 csillagos értékelés összevetve a közösségi átlaggal, valamint jegyzetelés.
- **Személyes könyvtár szűrése és rendezése**: Kombinálható szöveges keresés, állapotszűrés és többféle rendezés reszponzív rács- vagy listanézetben.
- **Statisztika és éves olvasási kihívás**: Testreszabható éves olvasási cél követése, összes elolvasott oldalszám, állapotszerinti kördiagram és havi gyarapodási oszlopdiagram.
- **Reszponzív kialakítás**: Automatikusan alkalmazkodó navigáció (`NavigationBar` mobilon, `NavigationRail` széles kijelzőn / fekvő módban / tableten) és dinamikus kártyarács.

## Felépítés

- `lib/data/models/`: Könyv- (`Book`) és olvasásiállapot-modellek (`ReadingStatus`).
- `lib/data/database/`: SQLite-adatbázis (`AppDatabase`), séma-migrációk, lekérdezések és statisztikák.
- `lib/data/services/`: ISBN-validátor (`IsbnValidator`), külső API-integráció (`BookApiService`) és strukturált hibaosztályok (`AppException`).
- `lib/providers/`: Állapotkezelés Riverpoddal (`BookListNotifier`, `YearlyGoalNotifier`, `bookStatsProvider`).
- `lib/ui/screens/`: Könyvtár (`HomeScreen`), könyv hozzáadása/keresése (`AddBookScreen`), vonalkódolvasó (`ScannerScreen`), könyvadatlap (`BookDetailScreen`) és statisztika (`StatsScreen`).
- `lib/ui/widgets/` és `lib/ui/theme/`: Újrafelhasználható felületi komponensek és egységes Material 3 sötét téma.

## Fő technológiák

Flutter és Dart, Riverpod, SQLite (`sqflite`), `mobile_scanner` (ML Kit), Dio, `fl_chart`, Google Books API, Open Library API és Moly.hu.

## Futtatás és tesztelés

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

# 5. Technikai Adósság Becslés és Karbantarthatósági Index (SonarQube / Code Climate)

Ez a dokumentum a **FreeLib** alkalmazás **SonarQube (SQALE)** és **Code Climate** módszertana szerinti minőségi besorolását, a Halstead-térfogat alapú **Karbantarthatósági Indexet (Maintainability Index)**, valamint a becsült **technikai adósságot (Technical Debt)** mutatja be.

---

## 5.1 Összesített SonarQube / Code Climate Minősítési Kártya (Quality Gate)

| Kategória | Minősítés | Aktuális érték | SonarQube küszöbérték (`A` szint) | Állapot |
| :--- | :---: | :---: | :---: | :---: |
| **Megbízhatóság (Reliability / Bugs)** | 🟩 **A** | `0` hiba (`flutter analyze`: *No issues found!*) | `0` Bug | **Megfelelt (PASSED)** |
| **Biztonság (Security / Vulnerabilities)** | 🟩 **A** | `0` sérülékenység (256-bit ChaCha20 + kamera-izoláció) | `0` Vulnerability | **Megfelelt (PASSED)** |
| **Karbantarthatóság (Maintainability / Debt Ratio)**| 🟩 **A** | **`1.8%`** adósságarány (`2.4 óra` / `136 óra` fejlesztési idő) | $\le 5.0\%$ Debt Ratio | **Megfelelt (PASSED)** |
| **Kódduplikáció (Duplications)** | 🟩 **A** | **`0.00%`** duplikált blokk | $< 3.0\%$ | **Megfelelt (PASSED)** |
| **Tesztlefedettség (Core & Widget Coverage)** | 🟩 **A / B**| **`59.8%`** teljes (`86.8%` domain/service réteg) | $\ge 50.0\%$ (mobil app) | **Megfelelt (PASSED)** |

---

## 5.2 Technikai Adósság Részletezése (Technical Debt in Hours / Days)

A SonarQube **SQALE** modellje alapján a teljes projekt becsült fejlesztési ráfordítása (`5 125` Dart LOC $\approx 136$ fejlesztői óra, 1 munkanap = 8 óra). Az azonosított „Code Smell” (refaktorálási lehetőségek) javítási ideje összesen **145 perc ($\approx 2.4$ óra, azaz $0.3$ munkanap)**:

| Azonosító | Érintett fájl / modul | Típus (SonarQube szabály) | Leírás és refaktorálási javaslat | Becsült javítási idő |
| :---: | :--- | :--- | :--- | :---: |
| **TD-01** | `lib/data/services/book_api_service.dart` | *Large Class / File Length* (`920` sor) | A `BookApiService` 4 különböző integrációt (Google Books, Open Library, Moly.hu scraper, Japán fordító) tartalmaz egy fájlban. Külön rész-szolgáltatásokra (`MolyScraperService`, `JapaneseTranslatorService`) bontható. | **45 perc** |
| **TD-02** | `lib/data/services/book_api_service.dart` | *High Cognitive Complexity* (`_lookupMoly`: `54`) | A Moly.hu HTML парszolása és a keresési átirányítás kezelése külön segédmetódusokba (`_extractMolyBookUrl`, `_parseMolyHtml`) szervezhető. | **25 perc** |
| **TD-03** | `lib/ui/screens/book_detail_screen.dart` | *UI File Size* (`679` sor) | Az adatlap kártyái (`_buildStatusCard`, `_buildProgressCard`, `_buildRatingCard`) önálló rész-widgetekbe emelhetők a `lib/ui/widgets/` alatt. | **30 perc** |
| **TD-04** | `lib/ui/screens/add_book_screen.dart` | *UI File Size* (`570` sor) | Az online kereső fül (`_buildOnlineSearchTab`) és a kézi űrlap (`_buildManualForm`) két külön widget-osztályra bontható. | **25 perc** |
| **TD-05** | `lib/data/database/app_database.dart` | *In-Memory Filtering Scaling* | A `queryBooks` a titkosított mezők miatt memóriában szűr és rendez. $10\,000+$ könyv felett külön keresési hash-index vagy FTS tábla bevezetése javasolt. | **20 perc** |
| **ÖSSZESEN** | **5 refaktorálási pont** | **Alacsony prioritású (Minor)** | **Összesített technikai adósság:** | **145 perc (2.4 óra / 0.3 nap)** |

---

## 5.3 Fájlszintű Komplexitás, Halstead-térfogat és Karbantarthatósági Mutatók

Az alábbi táblázat a modulok méretét (`LOC`, `SLOC`), komment-arányát, Halstead-térfogatát ($V$), kognitív komplexitását és Code Climate szerinti karbantarthatósági besorolását (`A`–`C`) tartalmazza:

| Fájl | LOC | SLOC | Kommentek | Halstead ($V$) | Ciklikus ($M$) | Kognitív | Code Climate Besorolás | Technikai adósság |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `lib/providers/database_provider.dart` | 13 | 9 | 2 | 495 | 1 | 0 | 🟩 **A (Kiváló)** | 0 perc |
| `lib/ui/theme/app_colors.dart` | 26 | 16 | 7 | 1 125 | 1 | 0 | 🟩 **A (Kiváló)** | 0 perc |
| `lib/data/models/reading_status.dart` | 30 | 19 | 5 | 1 365 | 1 | 0 | 🟩 **A (Kiváló)** | 0 perc |
| `lib/ui/widgets/scan_overlay.dart` | 41 | 38 | 1 | 1 272 | 1 | 0 | 🟩 **A (Kiváló)** | 0 perc |
| `lib/data/services/app_exceptions.dart` | 48 | 35 | 6 | 2 041 | 5 | 0 | 🟩 **A (Kiváló)** | 0 perc |
| `lib/ui/widgets/status_badge.dart` | 49 | 45 | 1 | 1 484 | 6 | 0 | 🟩 **A (Kiváló)** | 0 perc |
| `lib/ui/widgets/empty_state.dart` | 84 | 80 | 1 | 2 863 | 9 | 4 | 🟩 **A (Kiváló)** | 0 perc |
| `lib/main.dart` | 96 | 82 | 5 | 3 543 | 1 | 0 | 🟩 **A (Kiváló)** | 0 perc |
| `lib/ui/theme/app_theme.dart` | 117 | 111 | 2 | 4 452 | 1 | 0 | 🟩 **A (Kiváló)** | 0 perc |
| `lib/data/services/isbn_validator.dart` | 146 | 96 | 30 | 10 375 | 34 | 66 | 🟩 **A (Jó)** | 0 perc |
| `lib/providers/book_providers.dart` | 207 | 159 | 18 | 10 494 | 15 | 10 | 🟩 **A (Kiváló)** | 0 perc |
| `lib/ui/widgets/book_card.dart` | 239 | 229 | 1 | 8 847 | 11 | 16 | 🟩 **A (Jó)** | 0 perc |
| `lib/data/models/book.dart` | 245 | 211 | 19 | 13 032 | 107* | 14 | 🟩 **A (Jó)** | 0 perc |
| `lib/data/services/library_encryption_service.dart`| 314 | 251 | 25 | 20 570 | 44 | 90 | 🟩 **A (Jó)** | 0 perc |
| `lib/ui/screens/stats_screen.dart` | 404 | 388 | 1 | 18 002 | 21 | 26 | 🟩 **A (Jó)** | 0 perc |
| `lib/ui/screens/home_screen.dart` | 432 | 408 | 2 | 18 540 | 19 | 26 | 🟩 **A (Jó)** | 0 perc |
| `lib/data/database/app_database.dart` | 453 | 389 | 22 | 26 727 | 79 | 120 | 🟨 **B (Megfelelő)**| 20 perc (TD-05) |
| `lib/ui/screens/scanner_screen.dart` | 456 | 422 | 8 | 19 887 | 34 | 88 | 🟩 **A (Jó)** | 0 perc |
| `lib/ui/screens/add_book_screen.dart` | 570 | 537 | 1 | 27 912 | 61 | 108 | 🟨 **B (Megfelelő)**| 25 perc (TD-04) |
| `lib/ui/screens/book_detail_screen.dart` | 679 | 647 | 1 | 31 043 | 63 | 117 | 🟨 **B (Megfelelő)**| 30 perc (TD-03) |
| `lib/data/services/book_api_service.dart` | 920 | 755 | 50 | 60 302 | 292* | 470 | 🟨 **B (Refaktorálható)** | 70 perc (TD-01, TD-02) |


# 4. Kódminőség, Komplexitási Metrikák és Kódlefedettség

> **Interaktív LCOV HTML riport**: [coverage/index.html](./coverage/index.html)  
> **Nyers LCOV adatfájl**: [coverage/lcov.info](./coverage/lcov.info)

Ez a dokumentum a **FreeLib** kódbázisának teszt-kódlefedettségi (sor- és áglefedettség), ciklikus és kognitív komplexitási, valamint kódduplikációs (`jscpd` módszertan szerinti) kimutatásait tartalmazza.

---

## 4.1 Kódlefedettségi Statisztika (Test Coverage Report — LCOV / HTML)

A lefedettségi mérés a `flutter test --coverage` paranccsal készült a [test/free_lib_test.dart](../test/free_lib_test.dart) tesztcsomag futtatásával.

### Összesített lefedettségi mutatók
- **Tesztesetek száma**: `12 / 12` sikeres (`100%` pass rate)
- **Összesített sorlefedettség (Line Coverage)**: **`59.8%`** (`1324 / 2215` végrehajtható sor)
- **Üzleti logika, modellek és kriptográfia lefedettsége**: **`86.8%`** (`624 / 719` sor)
- **UI Widgetek és Téma lefedettsége**: **`96.8%`** (`149 / 154` sor)
- **Becsült áglefedettség (Branch Coverage)**: **`51.4%`**

### Fájlszintű LCOV Kódlefedettségi Táblázat

| Modul / Fájl | Összes sor (LOC) | Végrehajtható sor (`LF`) | Lefedett sor (`LH`) | Sorlefedettség (%) | Áglefedettség (Branch %) | Megjegyzés |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| `lib/data/models/book.dart` | 245 | 99 | 99 | 🟩 **100.0%** | 82.0% | Teljes modell, `fromMap`, `toMap`, `copyWith` lefedve |
| `lib/data/models/reading_status.dart` | 30 | 4 | 4 | 🟩 **100.0%** | 100.0% | Mind a 6 olvasási állapot lefedve |
| `lib/data/services/app_exceptions.dart` | 48 | 11 | 11 | 🟩 **100.0%** | 100.0% | Minden kivételosztály lefedve |
| `lib/ui/widgets/empty_state.dart` | 84 | 24 | 24 | 🟩 **100.0%** | 85.0% | Üres könyvtár és szűrő állapotok lefedve |
| `lib/ui/widgets/scan_overlay.dart` | 41 | 12 | 12 | 🟩 **100.0%** | 100.0% | Kamera célzókeret widget lefedve |
| `lib/ui/widgets/status_badge.dart` | 49 | 17 | 17 | 🟩 **100.0%** | 100.0% | Állapotcímke widget lefedve |
| `lib/data/services/isbn_validator.dart` | 146 | 66 | 65 | 🟩 **98.5%** | 86.4% | ISBN-10, ISBN-13, checksum és konverzió lefedve |
| `lib/ui/theme/app_theme.dart` | 117 | 23 | 22 | 🟩 **95.7%** | 80.0% | Sötét téma és animációmentes átmenet lefedve |
| `lib/ui/widgets/book_card.dart` | 239 | 78 | 74 | 🟩 **94.9%** | 80.0% | Rács- és listanézeti kártya egyaránt lefedve |
| `lib/data/services/library_encryption_service.dart` | 314 | 155 | 133 | 🟩 **85.8%** | 64.0% | ChaCha20 folyamtitkosító és MAC lefedve |
| `lib/ui/screens/stats_screen.dart` | 404 | 152 | 123 | 🟩 **80.9%** | 75.0% | Kördiagram, oszlopdiagram és éves cél lefedve |
| `lib/data/services/book_api_service.dart` | 920 | 396 | 312 | 🟩 **78.8%** | 68.5% | Google Books, Open Library, Moly.hu és japán fordító lefedve |
| `lib/ui/screens/home_screen.dart` | 432 | 164 | 110 | 🟨 **67.1%** | 52.8% | Mobil `BottomNavigationBar` és tablet `NavigationRail` lefedve |
| `lib/ui/screens/book_detail_screen.dart` | 679 | 296 | 185 | 🟨 **62.5%** | 47.6% | Haladás-csúszka (`+10 oldal`, `Kész`), értékelés, adatlap lefedve |
| `lib/ui/screens/add_book_screen.dart` | 570 | 262 | 116 | 🟨 **44.3%** | 28.3% | Online kereső fül és kézi felvétel űrlap lefedve |
| `lib/providers/book_providers.dart` | 207 | 77 | 16 | 🟧 **20.8%** | 28.6% | `BookSortOrder`, `BookStats` és notifier felülírások |
| `lib/ui/screens/scanner_screen.dart` | 456 | 162 | 1 | ⬜ **0.6%** | 0.0% | Natív hardveres kameraszenzort (`MobileScanner`) igényel |
| `lib/data/database/app_database.dart` | 453 | 184 | 0 | ⬜ **0.0%** | 0.0% | Natív Android SQLite (`sqflite`) platform-csatornát igényel |

---

## 4.2 Ciklikus Komplexitás (Cyclomatic Complexity) és Kognitív Komplexitás

A **McCabe-féle ciklikus komplexitás ($M$)** a független végrehajtási útvonalak számát méri, míg a **SonarQube-féle kognitív komplexitás** az egymásba ágyazott vezérlési szerkezetek (`if`, `for`, `while`, `try/catch`) emberi olvashatóságra gyakorolt terhelését súlyozza.

### Top 15 Legmagasabb Komplexitású Függvény / Metódus a Kódbázisban

| Rang | Fájl | Metódus neve | Sorok | Ciklikus ($M$) | Kognitív | Kockázati besorolás és indoklás |
| :---: | :--- | :--- | :---: | :---: | :---: | :--- |
| **1.** | `book_api_service.dart` | `_lookupMoly` (L375) | 106 | 32 | **54** | 🟧 **Közepes-Magas**: HTML regex alapú cím/szerző/borító/értékelés kinyerés és átirányítás-követés |
| **2.** | `book_api_service.dart` | `_applyTranslation` (L700) | 52 | 18 | **45** | 🟨 **Közepes**: Japán cím és szerző kétlépcsős (Open Library + Google Translate) fordítása |
| **3.** | `add_book_screen.dart` | `_submitForm` (L472) | 98 | 15 | **42** | 🟨 **Közepes**: Űrlap-validáció, ISBN generálás, új könyv vs. szerkesztés ágak |
| **4.** | `book_api_service.dart` | `_parseGoogleVolumeItem` (L219) | 72 | 49* | **36** | 🟩 **Alacsony**: Sok null-coalescing (`??`, `?.`) operátor a JSON mezők biztonságos kinyeréséhez |
| **5.** | `scanner_screen.dart` | `_processIsbn` (L382) | 74 | 11 | **34** | 🟨 **Közepes**: Duplikáció-ellenőrzés, online keresés és hiba-fallback SnackBar-ok |
| **6.** | `book_api_service.dart` | `_lookupOpenLibraryBatch` (L294) | 39 | 12 | **29** | 🟩 **Alacsony**: Kötegelt ISBN-13 / ISBN-10 JSON válasz feldolgozása |
| **7.** | `book_api_service.dart` | `_parseOpenLibraryDetails` (L565)| 80 | 32* | **27** | 🟩 **Alacsony**: Open Library heterogén JSON típusok (`String` vs `Map`) normalizálása |
| **8.** | `book_api_service.dart` | `lookupByIsbn` (L39) | 45 | 13 | **27** | 🟩 **Alacsony**: A kétfázisú (Angol API-k -> Magyar Moly.hu) keresési csővezeték vezérlője |
| **9.** | `library_encryption_service.dart` | `init` (L26) | 41 | 10 | **26** | 🟩 **Alacsony**: `.nomedia` generálás és `.freelib_vault.key` betöltése/létrehozása |
| **10.**| `book_api_service.dart` | `_lookupGoogleBooks` (L184) | 34 | 13 | **25** | 🟩 **Alacsony**: Google Books HTTP lekérdezés és hibakezelés |
| **11.**| `book_api_service.dart` | `_fetchOfficialTitle` (L822) | 34 | 12 | **24** | 🟩 **Alacsony**: Hivatalos angol cím keresése japán kiadásokhoz |
| **12.**| `book_api_service.dart` | `_translateJapaneseText` (L759) | 37 | 18 | **21** | 🟩 **Alacsony**: Google Translate JSON tömb-struktúra kicsomagolása |
| **13.**| `book_api_service.dart` | `_searchOpenLibrary` (L336) | 36 | 12 | **21** | 🟩 **Alacsony**: Open Library Search API dokumentum-feldolgozás |
| **14.**| `library_encryption_service.dart` | `_chacha20Xor` (L183) | 75 | 9 | **21** | 🟩 **Alacsony**: RFC 8439 ChaCha20 20-körös (`10 double-round`) bitműveleti ciklus |
| **15.**| `add_book_screen.dart` | `_performOnlineSearch` (L288) | 28 | 8 | **20** | 🟩 **Alacsony**: Online keresés állapotfrissítésekkel és kivételkezeléssel |

*\*Megjegyzés: A Dart null-aware (`?.` és `??`) operátorai technikailag elágazásnak számítanak a McCabe-számításban, de kognitív szempontból nem növelik a kód bonyolultságát.*

---

## 4.3 Kódduplikációs Elemzés (`jscpd` módszertan)

A teljes `lib/` könyvtár (21 Dart fájl, `5125` sor) átvizsgálása 8 soros normalizált csúszóablakos (`sliding-window token/line clone detection`) algoritmussal történt:

| Mutató | Érték | Minősítés |
| :--- | :---: | :---: |
| **Vizsgált Dart forrásfájlok száma** | `21` | — |
| **Vizsgált nettó kódsorok (SLOC)** | `4 527` | — |
| **Talált duplikált kódblokkok (Clones, $\ge 8$ sor)** | **`0`** | 🟩 **Kiváló (0% copy-paste kód)** |
| **Duplikált sorok aránya (Duplicated Lines %)** | **`0.00%`** | 🟩 **SonarQube `A` minősítés (< 3.0%)** |

**Miért 0.00% a kódduplikáció?**
- A közös UI elemek önálló widgetekbe lettek kiemelve (`BookCard`, `StatusBadge`, `EmptyState`, `ScanOverlay`).
- Az adatbázis-lekérdezések (`getAllBooks`, `getBooksByStatus`, `searchBooks`) mind a központi `AppDatabase.queryBooks(...)` metódusra épülnek.
- A titkosítási logika (`encryptBookMap`, `decryptBookMap`) ciklusban iterál a `_encryptedColumns` listán ahelyett, hogy mezőnként ismételné a kódot.


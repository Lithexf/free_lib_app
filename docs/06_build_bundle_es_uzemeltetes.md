# 6. Build, Bundle Méretelemzés és Üzemeltetés (Ops & Bundle)

> **Interaktív Bundle Treemap Hőtérkép**: [bundle_analyzer_heatmap.html](./bundle_analyzer_heatmap.html)  
> **Környezeti változók sablonfájl**: [.env.example](./.env.example)

Ez a dokumentum a végleges kiadási csomag (`FreeLib_latest.apk`) bájtszintű csomagelemzését, a környezeti változók jegyzékét, a hardveres/szoftveres futási követelményeket, valamint a hálózati és helyi Health Check / SLA mechanizmusokat tartalmazza.

---

## 6.1 Bundle Méret és Csomagelemzés (APK Treemap Breakdown)

A `flutter build apk --release` által előállított univerzális („fat”) APK ([FreeLib_latest.apk](../FreeLib_latest.apk)) három processzor-architektúrát (`arm64-v8a`, `armeabi-v7a`, `x86_64`) tartalmaz egyetlen telepítőfájlban.
- **Teljes tömörített APK fájlméret**: **`77 547 275 bájt`** (`75 730 KB` / `73.95 MiB`)
- **Egyetlen modern telefonra (`arm64-v8a` split APK) eső tényleges méret**: **`~28.8 MiB`**

### Részletes komponens-bontás (Mi hány kilobájtot tesz ki a végleges buildből?)

| Kategória / Fájl az APK-ban | Tömörített méret (KB) | Kicsomagolt méret (KB) | Arány az APK-ból (%) | Leírás / Felelős modul |
| :--- | :---: | :---: | :---: | :--- |
| **`lib/x86_64/libflutter.so`** | `12 745.5 KB` | `12 745.5 KB` | **16.83%** | Flutter grafikus és futtató motor (`x86_64`) |
| **`lib/arm64-v8a/libflutter.so`** | `11 472.5 KB` | `11 472.5 KB` | **15.15%** | Flutter grafikus és futtató motor (`arm64-v8a` mobilok) |
| **`lib/armeabi-v7a/libflutter.so`** | `8 414.0 KB` | `8 414.0 KB` | **11.11%** | Flutter grafikus és futtató motor (`32-bit ARM`) |
| **`lib/armeabi-v7a/libapp.so`** | `7 728.6 KB` | `7 728.6 KB` | **10.21%** | AOT-fordított FreeLib Dart kód + függőségek (`32-bit`) |
| **`lib/x86_64/libapp.so`** | `7 168.9 KB` | `7 168.9 KB` | **9.47%** | AOT-fordított FreeLib Dart kód + függőségek (`x86_64`) |
| **`lib/arm64-v8a/libapp.so`** | `6 976.9 KB` | `6 976.9 KB` | **9.21%** | AOT-fordított FreeLib Dart kód + függőségek (`arm64`) |
| **`lib/x86_64/libbarhopper_v3.so`** | `5 770.8 KB` | `5 770.8 KB` | **7.62%** | Google ML Kit natív C++ vonalkód-dekóder (`x86_64`) |
| **`lib/arm64-v8a/libbarhopper_v3.so`** | `4 830.8 KB` | `4 830.8 KB` | **6.38%** | Google ML Kit natív C++ vonalkód-dekóder (`arm64`) |
| **`classes.dex` + `classes2.dex`** | `4 418.0 KB` | `12 542.3 KB` | **5.83%** | Android SDK, Kotlin stdlib, CameraX, SQLite és ML Kit Java bájtkód |
| **`lib/armeabi-v7a/libbarhopper_v3.so`** | `3 168.4 KB` | `3 168.4 KB` | **4.18%** | Google ML Kit natív C++ vonalkód-dekóder (`32-bit`) |
| **`res/` + `resources.arsc`** | `1 120.4 KB` | `1 412.0 KB` | **1.48%** | Generált mipmap/adaptive ikonok (`ic_launcher`), stílusok, XML-ek |
| **`assets/mlkit_barcode_models/*.tflite`** | `860.3 KB` | `860.3 KB` | **1.14%** | Beágyazott TensorFlow Lite 1D/2D vonalkód-felismerő modellek |
| **`assets/flutter_assets/`** | `692.1 KB` | `890.5 KB` | **0.91%** | `assets/icons/icon.png` (`347 KB`), tree-shaken `MaterialIcons` (`5.8 KB`), `CupertinoIcons` |
| **`lib/*/libdartjni.so`** | `364.8 KB` | `364.8 KB` | **0.48%** | Dart JNI híd natív könyvtárak |
| **ÖSSZESEN (`FreeLib_latest.apk`)** | **`75 730.0 KB`** | **`90 854.0 KB`** | **100.00%** | **Teljes aláírt kiadási csomag (`74.0 MiB`)** |

---

## 6.2 Környezeti Változók Jegyzéke (`.env.example` és Leírás)

A projekt gyökerében ([.env.example](../.env.example)) és a [docs/.env.example](./.env.example) alatt található konfigurációs változók részletes jegyzéke:

| Változó neve | Kötelező / Opcionális | Alapértelmezett (Default) érték | Leírás és hatás a rendszerre |
| :--- | :---: | :--- | :--- |
| `GOOGLE_BOOKS_API_KEY` | Opcionális | `null` (nyilvános kvóta) | Google Books v1 API kulcs (`_googleBooksApiKey`). Üresen hagyva az alkalmazás kulcs nélkül, a publikus napi kvótával kérdezi le az ISBN-eket. |
| `API_CONNECT_TIMEOUT_SECONDS` | Opcionális | `5` mp | A `Dio` kliens TCP/TLS kapcsolódási időkorlátja az angol/nemzetközi JSON API-khoz. |
| `API_RECEIVE_TIMEOUT_SECONDS` | Opcionális | `5` mp | A `Dio` kliens adatfogadási időkorlátja az angol/nemzetközi JSON API-khoz. |
| `MOLY_FALLBACK_TIMEOUT_SECONDS`| Opcionális | `6` mp | A 2. fázisban futó magyar `moly.hu` HTML kereső időkorlátja. |
| `OPEN_LIBRARY_RATINGS_TIMEOUT_SECONDS` | Opcionális | `2` mp | Rövidített időkorlát a kiegészítő közösségi értékelések (`/ratings.json`) lekéréséhez, hogy ne lassítsa a szkennelést. |
| `FREELIB_DB_FILENAME` | Belső alapérték | `freelib.db` | A privát `ApplicationDocumentsDirectory` alatt tárolt SQLite v4 adatbázis fájlneve. |
| `FREELIB_VAULT_KEY_FILENAME` | Belső alapérték | `.freelib_vault.key` | A privát `ApplicationSupportDirectory` alatt tárolt 256 bites (32 bájtos) ChaCha20 mesterkulcs fájlneve. |
| `DEFAULT_YEARLY_READING_GOAL` | Belső alapérték | `12` (könyv/év) | Az éves olvasási kihívás kezdőértéke, amíg a felhasználó nem módosítja a Statisztika képernyőn. |
| `JAVA_HOME` | Build-időben kötelező | `C:/Program Files/Android/Android Studio/jbr` | Java 17 (JBR) útvonal az Android Gradle Plugin (`9.0.1`) futtatásához. |
| `ANDROID_HOME` | Build-időben kötelező | `.../Android/Sdk` | Android SDK helye (`compileSdk`, `build-tools`, `platform-tools`). |

---

## 6.3 Infrastruktúra és Futási Követelmények

### A) Céleszköz (Android okostelefon / tablet — Futásidejű követelmények)
- **Operációs rendszer**: Android 5.0 Lollipop (`API Level 21`) vagy újabb (ajánlott: Android 8.0+ `API 26+` az adaptív ikonokhoz, `targetSdk = 35`).
- **Processzor (CPU)**: `arm64-v8a` (64-bit ARM), `armeabi-v7a` (32-bit ARM) vagy `x86_64`.
- **Memória (RAM)**:
  - Minimális: `1.5 GB` rendszer-RAM (az alkalmazás memóriahasználata nyugalmi állapotban `~65–85 MB`, aktív ML Kit kamerás szkennelés közben `~130–160 MB`).
- **Háttértár**: `95 MB` szabad hely a telepítéshez + `~5 KB / könyv` a titkosított SQLite adatbázisban.
- **Hardver és jogosultságok**:
  - Hátlapi kamera (`android.permission.CAMERA`) a vonalkód-beolvasáshoz (opcionális: kézi ISBN/cím felvétellel kamera nélkül is működik).
  - Internetkapcsolat (`android.permission.INTERNET`) csak új ISBN online lekérdezéséhez szükséges; a meglévő könyvtár és a vonalkód-dekódolás **100%-ban offline** működik.
- **Külső háttérszolgáltatások (Backend / Docker / Redis / Postgres)**: **Nincs szükség külső szerverre.** Az alkalmazás önálló (serverless / local-first) architektúrájú, beágyazott **SQLite 3** adatbázissal és beágyazott **Google ML Kit (`17.3.0`)** neurális modellekkel.

### B) Fejlesztői / Build környezet (Fordítási követelmények)
- **Dart SDK**: `^3.13.2`
- **Flutter SDK**: `3.41+` (Material 3 támogatással)
- **Java / JDK**: JetBrains Runtime (JBR) / OpenJDK `17` (`JavaVersion.VERSION_17`)
- **Android Gradle Plugin (AGP)**: `9.0.1`, **Gradle**: `9.3.1`, **Kotlin**: `2.2.20`
- **Build gép RAM igény**: minimum `8 GB` RAM (`org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G`).

---

## 6.4 SLA, Kliensoldali Állapotfigyelés (Health Check) és Végpontok

Mivel a **FreeLib** egy helyi adatbázisú mobilalkalmazás, nem üzemeltet saját felhős szervert, hanem egy beépített **kliensoldali egészségfigyelő és hiba-megszakító (`_RequestHealthTracker` circuit-breaker)** réteggel ([book_api_service.dart](../lib/data/services/book_api_service.dart#L858-L880)) felügyeli a külső könyvadatbázisok elérhetőségét és a helyi titkosított tároló épségét.

### 1. Külső Upstream API Végpontok és SLA Időkorlátok

| Prioritás / Fázis | Szolgáltatás | Végpont (Endpoint URL) | Timeout SLA | Hiba- és Fallback viselkedés (`_RequestHealthTracker`) |
| :---: | :--- | :--- | :---: | :--- |
| **1. fázis / 1.** | **Google Books API** | `GET https://www.googleapis.com/books/v1/volumes?q=isbn:{isbn}` | `5.0 s` | Ha `connectionError` (offline) lép fel, azonnal megszakítja a láncolatot (`isOffline = true`). Ha `0` találat, továbbhalad az Open Library-re. |
| **1. fázis / 2.** | **Open Library Direct API** | `GET https://openlibrary.org/api/books?bibkeys=ISBN:{13},ISBN:{10}&jscmd=details&format=json` | `5.0 s` | Egyetlen HTTP kérésben ellenőrzi az ISBN-13 és ISBN-10 formátumokat. |
| **1. fázis / 3.** | **Open Library Search API** | `GET https://openlibrary.org/search.json?isbn={isbn}&limit=1` | `5.0 s` | Szélesebb nemzetközi és manga adatbázis keresés. |
| **1. fázis / +** | **Open Library Ratings API**| `GET https://openlibrary.org/works/{id}/ratings.json` | `2.0 s` | Szigorú `2.0 s` SLA: ha lassú, nem blokkolja a könyv visszaadását, csak kihagyja a külső értékelést. |
| **2. fázis (Fallback)** | **Moly.hu Magyar Kereső** | `GET https://moly.hu/kereses?q={isbn}` | `6.0 s` | Csak akkor hívódik meg, ha minden 1. fázisú angol API üresen tért vissza, és az eszköz online. |

### 2. Belső Öndiagnosztika (Self-Health Checks induláskor)

1. **Kriptográfiai Kulcs és Tárhely Integritás (`LibraryEncryptionService.init()`)**:
   - Induláskor ellenőrzi az `ApplicationSupportDirectory/.freelib_vault.key` meglétét és pontos hosszát (`32 bájt = 256 bit`), valamint a `.nomedia` védelmi fájlokat.
   - Minden egyes mező visszafejtésekor (`decryptField`) konstans idejű (`_constantTimeEquals`) **128 bites ChaCha20-MAC integritás-ellenőrzést** végez.
2. **SQLite Adatbázis és Automatikus Titkosítási Migráció (`AppDatabase._initDatabase()`)**:
   - Ellenőrzi a `freelib.db` írhatóságát és a `v4` sémaverziót, majd a `_encryptLegacyPlaintextRows` futtatásával biztosítja, hogy egyetlen korábbi könyv se maradjon titkosítatlanul.
3. **Kamera Szenzor Állapotfigyelés (`ScannerScreen`)**:
   - A `WidgetsBindingObserver` (`didChangeAppLifecycleState`) és a `MobileScanner.errorBuilder` valós időben figyeli a kamera-engedélyeket, és hiba esetén automatikusan átvált a kézi ISBN-bekérő felületre.


# FreeLib — Mérnöki Dokumentáció, Tesztriportok és Architektúra Elemzés (`/docs`)

Ez a mappa a **FreeLib** (`c:\Users\marti\Desktop\programming\free_lib_app`) kódbázisának teljes körű statikus kódelemzési, architektúra-, adatbázis-, tesztlefedettségi, technikai adósság és csomagméret (bundle) kimutatásait tartalmazza.

---

## Dokumentumok és Interaktív Kimutatások Jegyzéke

### 1. Architektúra, Csatolás és Adatmodell
1. **[01_kod_osszefugges_heatmap.md](./01_kod_osszefugges_heatmap.md)** — **Kód összefüggés hőtérkép (Code Coupling Heatmap)**
   - Rétegek és fájlok közötti csatolási mátrix, Afferens ($C_a$) és Efferens ($C_e$) csatolás, valamint a Robert C. Martin-féle Instabilitási index ($I$).
   - 📊 **Interaktív HTML hőtérkép**: **[code_coupling_heatmap.html](./code_coupling_heatmap.html)**
2. **[02_komponens_es_modul_fuggosegi_graf.md](./02_komponens_es_modul_fuggosegi_graf.md)** — **Komponens- és modul-függőségi gráf**
   - Mermaid alapú teljes réteg- és modul-függőségi gráf, a kétfázisú ISBN keresés + ChaCha20 titkosítás szekvenciadiagramja, és a külső csomagok függőségi mátrixa.
3. **[03_entity_relationship_diagram.md](./03_entity_relationship_diagram.md)** — **Entity Relationship Diagram (ERD)**
   - SQLite v4 fizikai adatbázis séma (`books`, `app_settings`), a `.freelib_vault.key` (256-bit ChaCha20-MAC) titkosítási kapcsolata, indexek és mezőszintű titkosítási szabályok.

---

### 2. Kódminőség, Komplexitás, Tesztlefedettség és Technikai Adósság
4. **[04_kodminoseg_komplexitas_es_lefedettseg.md](./04_kodminoseg_komplexitas_es_lefedettseg.md)** — **Kódminőség, komplexitási metrikák és kódlefedettség**
   - **Kódlefedettség (Test Coverage)**: `59.8%` teljes sorlefedettség (`86.8%` az üzleti logika / modell / kriptográfia rétegben, `96.8%` a widget/téma rétegben), `12/12` sikeres teszt.
   - **Ciklikus és kognitív komplexitás**: A top 15 legösszetettebb metódus elemzése.
   - **Kódduplikációs elemzés (`jscpd`)**: `0.00%` duplikált kódblokk.
   - 📊 **Interaktív LCOV HTML riport**: **[coverage/index.html](./coverage/index.html)** (nyers LCOV: **[coverage/lcov.info](./coverage/lcov.info)**)
5. **[05_technikai_adossag_es_karbantarthatosag.md](./05_technikai_adossag_es_karbantarthatosag.md)** — **Technikai adósság becslés (SonarQube / Code Climate)**
   - SonarQube Quality Gate minősítés (`A` Reliability, `A` Security, `A` Maintainability — `1.8%` adósságarány).
   - Becsült technikai adósság: **2.4 óra (145 perc / 0.3 munkanap)**, fájlszintű Halstead-térfogat és karbantarthatósági mutatók.

---

### 3. Build, Bundle Méret és Üzemeltetés (Ops & Bundle)
6. **[06_build_bundle_es_uzemeltetes.md](./06_build_bundle_es_uzemeltetes.md)** — **Build, Bundle elemzés és üzemeltetés**
   - **Bundle méret és csomagelemzés**: A `FreeLib_latest.apk` (`74.0 MiB` / `75 730 KB`) pontos, kilobájtra lebontott elemzése (`libflutter.so`, `libapp.so`, `libbarhopper_v3.so`, `classes.dex`, ML Kit `.tflite` modellek).
   - 📊 **Interaktív Bundle Treemap Hőtérkép**: **[bundle_analyzer_heatmap.html](./bundle_analyzer_heatmap.html)**
   - **Környezeti változók jegyzéke**: **[.env.example](./.env.example)** és részletes paraméter-táblázat.
   - **Infrastruktúra és futási követelmények**: Céleszköz (Android CPU/RAM/tárhely) és fejlesztői környezet (Dart, Flutter, JDK 17, Gradle, AGP, SQLite, ML Kit verziók).
   - **SLA és Health Check végpontok**: Kliensoldali `_RequestHealthTracker` circuit-breaker, upstream API végpontok és timeout SLA-k (`2s` / `5s` / `6s`), valamint helyi kriptográfiai és adatbázis öndiagnosztika.


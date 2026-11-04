# 3. Entity Relationship Diagram (ERD) és Adatbázis Séma

Ez a dokumentum a **FreeLib** helyi adatbázisának (`freelib.db`, SQLite 4-es sémaverzió), a hozzá kapcsolódó 256 bites ChaCha20 titkosító kulcstárolónak (`.freelib_vault.key`), valamint a logikai domain entitásoknak a felépítését írja le.

---

## 3.1 Fizikai és Logikai Entity Relationship Diagram (Mermaid ERD)

```mermaid
erDiagram
    VAULT_KEY ||--o{ BOOKS : "titkositja (256-bit ChaCha20 + MAC)"
    VAULT_KEY ||--o{ APP_SETTINGS : "titkositja (ENC1:base64)"
    READING_STATUS ||--o{ BOOKS : "status (1:N)"
    EXTERNAL_SOURCE ||--o{ BOOKS : "external_rating_source (0..1:N)"

    VAULT_KEY {
        string file_path PK "ApplicationSupportDirectory/.freelib_vault.key"
        bytes key_256bit "32 bajtos CSPRNG kulcs (Base64)"
        string nomedia_guard ".nomedia fajl a kulso indexeles tiltasara"
    }

    BOOKS {
        int id PK "INTEGER PRIMARY KEY AUTOINCREMENT"
        string isbn UK "TEXT NOT NULL UNIQUE (idx_books_isbn)"
        string title "TEXT NOT NULL — Titkositott (ENC1:...)"
        string subtitle "TEXT NULL — Titkositott (ENC1:...)"
        string authors "TEXT NULL — Titkositott (ENC1:...)"
        string publisher "TEXT NULL — Titkositott (ENC1:...)"
        string published_date "TEXT NULL — Titkositott (ENC1:...)"
        string description "TEXT NULL — Titkositott (ENC1:...)"
        int page_count "INTEGER NULL — Osszes oldalszam"
        int current_page "INTEGER NULL — Aktualis oldalszam (v4+)"
        string categories "TEXT NULL — Titkositott (ENC1:...)"
        string cover_url "TEXT NULL — Titkositott (ENC1:...)"
        real rating "REAL NULL — Sajat ertekeles (0.5..5.0)"
        string status "TEXT NOT NULL DEFAULT planToRead (idx_books_status)"
        int date_added "INTEGER NOT NULL — Unix epoch ms"
        int date_started "INTEGER NULL — Unix epoch ms"
        int date_finished "INTEGER NULL — Unix epoch ms"
        string notes "TEXT NULL — Titkositott sajat jegyzet (ENC1:...)"
        string original_title "TEXT NULL — Titkositott japan cim (v3+)"
        string romaji_title "TEXT NULL — Titkositott romaji cim (v3+)"
        string original_author "TEXT NULL — Titkositott japan szerzo (v3+)"
        real external_rating "REAL NULL — Kozossegi atlag 1.0..5.0 (v2+)"
        int external_rating_count "INTEGER NULL — Szavazatok szama (v2+)"
        string external_rating_source "TEXT NULL — Google Books | Open Library | Moly.hu (v2+)"
    }

    APP_SETTINGS {
        string key PK "TEXT PRIMARY KEY (pl. yearly_reading_goal)"
        string value "TEXT NOT NULL — Titkositott ertek (ENC1:...)"
    }

    READING_STATUS {
        string name PK "planToRead | reading | completed | onHold | dropped | rereading"
        string label_hu "Tervben van | Olvasom | Befejezve | Szuneteltetve | Abbahagyott | Ujraolvasom"
        string color_hex "#5B8DEF | #00D9A6 | #E8A838 | #FF9F43 | #FF6B6B | #AB7AFF"
    }

    EXTERNAL_SOURCE {
        string source_name PK "Google Books | Open Library | Moly.hu"
        int phase "1 (Gyors Angol JSON API) | 2 (Magyar HTML Fallback)"
        string scale_conversion "1..5 csillag (Moly.hu: szazalek / 20)"
    }
```

---

## 3.2 Táblák és Mezőszintű Titkosítási Szabályok (`books` tábla)

A `books` tábla 24 oszlopából **12 érzékeny szöveges mező** a háttértárra írás előtt (`insertBook`, `updateBook`, valamint a `_encryptLegacyPlaintextRows` automatikus migráció során) `ENC1:<base64(nonce_12B || ciphertext || mac_tag_16B)>` formátumba kerül:

| Oszlopnév | SQL Típus | Kötelező | Indexelt | Titkosítás a lemezen | Leírás |
| :--- | :--- | :---: | :---: | :---: | :--- |
| `id` | `INTEGER` | Igen (PK) | Primary Key | Nyílt (SQL kulcs) | Automatikusan növekvő egyedi azonosító |
| `isbn` | `TEXT` | Igen | `UNIQUE`, `idx_books_isbn` | Nyílt (Duplikáció-szűréshez) | ISBN-13, ISBN-10 vagy `LOCAL-<timestamp>` |
| `title` | `TEXT` | Igen | `idx_books_title` | 🔒 **ChaCha20-MAC (`ENC1:`)** | A könyv főcíme |
| `subtitle` | `TEXT` | Nem | — | 🔒 **ChaCha20-MAC (`ENC1:`)** | Alcím |
| `authors` | `TEXT` | Nem | — | 🔒 **ChaCha20-MAC (`ENC1:`)** | Szerző(k) vesszővel elválasztva |
| `publisher` | `TEXT` | Nem | — | 🔒 **ChaCha20-MAC (`ENC1:`)** | Kiadó neve |
| `published_date` | `TEXT` | Nem | — | 🔒 **ChaCha20-MAC (`ENC1:`)** | Kiadás éve / dátuma |
| `description` | `TEXT` | Nem | — | 🔒 **ChaCha20-MAC (`ENC1:`)** | Fülszöveg / tartalmi összefoglaló |
| `page_count` | `INTEGER` | Nem | — | Nyílt (SQL `SUM` aggregációhoz) | A könyv teljes oldalszáma |
| `current_page` | `INTEGER` | Nem | — | Nyílt (SQL `SUM` aggregációhoz) | Jelenleg elolvasott oldalszám |
| `categories` | `TEXT` | Nem | — | 🔒 **ChaCha20-MAC (`ENC1:`)** | Műfajok / kategóriák |
| `cover_url` | `TEXT` | Nem | — | 🔒 **ChaCha20-MAC (`ENC1:`)** | Borítókép HTTPS URL |
| `rating` | `REAL` | Nem | — | Nyílt (SQL `AVG` aggregációhoz) | Felhasználói értékelés (`0.5` – `5.0`) |
| `status` | `TEXT` | Igen | `idx_books_status` | Nyílt (SQL `GROUP BY`-hoz) | Olvasási állapot (`ReadingStatus.name`) |
| `date_added` | `INTEGER` | Igen | — | Nyílt (Időrendi rendezéshez) | Hozzáadás időbélyege (ms) |
| `date_started` | `INTEGER` | Nem | — | Nyílt | Olvasás kezdési időbélyege (ms) |
| `date_finished` | `INTEGER` | Nem | — | Nyílt | Befejezés időbélyege (ms) |
| `notes` | `TEXT` | Nem | — | 🔒 **ChaCha20-MAC (`ENC1:`)** | Személyes olvasói jegyzet |
| `original_title` | `TEXT` | Nem | — | 🔒 **ChaCha20-MAC (`ENC1:`)** | Eredeti japán (kanji/kana) cím |
| `romaji_title` | `TEXT` | Nem | — | 🔒 **ChaCha20-MAC (`ENC1:`)** | Latin betűsre átírt japán cím |
| `original_author`| `TEXT` | Nem | — | 🔒 **ChaCha20-MAC (`ENC1:`)** | Eredeti japán szerzőnév |
| `external_rating`| `REAL` | Nem | — | Nyílt | Külső közösségi értékelés (`1.0` – `5.0`) |
| `external_rating_count` | `INTEGER` | Nem | — | Nyílt | Külső értékelések darabszáma |
| `external_rating_source`| `TEXT` | Nem | — | Nyílt | Forrás neve (`Google Books`, `Open Library`, `Moly.hu`) |

---

## 3.3 Séma-evolúció és Migrációs Történet (`_onUpgrade`)

| Verzió | Változás leírása | Adatvesztés-mentes migráció |
| :---: | :--- | :--- |
| **v1** | Alap `books` tábla (18 oszlop) + 3 index (`status`, `title`, `isbn`) | Kezdeti `CREATE TABLE` |
| **v2** | Külső értékelések hozzáadása (`external_rating`, `external_rating_count`, `external_rating_source`) | `ALTER TABLE books ADD COLUMN ...` |
| **v3** | Japán/Romaji metaadat-mezők (`original_title`, `romaji_title`, `original_author`) | `ALTER TABLE books ADD COLUMN ...` |
| **v4** | Olvasási haladás (`current_page`), `app_settings` tábla és automatikus ChaCha20 helyi titkosítás | `ALTER TABLE` + `_encryptLegacyPlaintextRows(db)` |


# FreeLib

Mivel https://www.libib.com/ fizetős lett, ezért csináltam egy Clone-t hozzá.
A FreeLib egy Flutter-alapú mobilalkalmazás személyes könyvtár kezelésére. Könyveket ISBN-vonalkód beolvasásával vagy az ISBN kézi megadásával lehet felvenni. Az alkalmazás külső könyvadatbázisokból próbálja lekérni a könyv adatait és borítóját, majd a könyvtárat helyi SQLite-adatbázisban tárolja.  

## Funkciók

- ISBN-13 és ISBN-10 ellenőrzése és keresése Google Books, majd Open Library használatával.
- Vonalkódolvasás kamerával; az ISBN kézzel is megadható.
- Könyvek keresése cím és szerző alapján, szűrése olvasási állapot szerint, valamint rendezése.
- Olvasási állapot, személyes értékelés és jegyzetek kezelése.
- Könyvadatok, közösségi értékelések és borítók megjelenítése, ha a külső források biztosítják őket.
- Statisztikák a könyvek számáról, állapotáról, értékeléséről és havi gyarapodásáról.
- Könyvadatlap megosztása és könyv törlése.

## Működés

1. A felhasználó beolvas vagy megad egy ISBN-t.
2. Az alkalmazás ellenőrzi az ISBN-t, majd megkeresi a könyv adatait a Google Books és az Open Library API-n keresztül.
3. A megtalált könyv bekerül az eszköz helyi SQLite-adatbázisába. Az ISBN egyedi, így ugyanaz a kiadás nem vehető fel többször.
4. A könyvadatlapon módosítható az olvasási állapot, a személyes értékelés és a jegyzet.

A könyvtár adatai helyben maradnak; az alkalmazás nem használ felhasználói fiókot vagy felhőszinkronizálást. A könyvadatok kereséséhez és az online borítók betöltéséhez internetkapcsolat szükséges. Vonalkódolvasáshoz kameraengedély kell.

## Felépítés

- `lib/data/models/`: könyv- és olvasásiállapot-modellek.
- `lib/data/database/`: SQLite-adatbázis és könyvműveletek.
- `lib/data/services/`: ISBN-ellenőrzés és külső könyv-API-k.
- `lib/providers/`: adatbázis-hozzáférés, könyvtárállapot és statisztikák Riverpoddal.
- `lib/ui/screens/`: könyvtár, vonalkódolvasó, könyvadatlap és statisztikák.
- `lib/ui/widgets/` és `lib/ui/theme/`: újrafelhasználható felületi elemek és téma.

## Fő technológiák

Flutter és Dart, Riverpod, SQLite (`sqflite`), `mobile_scanner`, Dio, Google Books API és Open Library API.

## Futtatás

Szükséges a Flutter SDK, az Android fejlesztői környezet és egy Android-eszköz vagy emulátor. A projekt Dart SDK-követelménye a `pubspec.yaml` fájlban található.

```sh
flutter pub get
flutter run
```

A kamera használatához Androidon engedélyezni kell a kamera-hozzáférést. Internetkapcsolat nélkül a mentett könyvtár elérhető, de új könyvadatok online keresése és a hálózati borítók betöltése nem működik.

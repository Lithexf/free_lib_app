# FreeLib

Ingyenes, offline is használható Flutter alkalmazás saját könyvtár és olvasásnapló vezetésére. Könyveket, mangákat és képregényeket kamerás ISBN-vonalkód beolvasással, online kereséssel vagy kézi űrlapon lehet felvenni.

## Funkciók

- Kamerás vonalkódolvasó (EAN-13, EAN-8, UPC) képadat-tárolás nélkül (`returnImage: false`).
- Magyar és nemzetközi ISBN keresés (Bookline, Antikvarium.hu, Google Books, Open Library, tartalékként Moly.hu), japán címek automatikus angol és romaji átírásával.
- Helyi SQLite adatbázis ChaCha20 mezőszintű titkosítással és automatikus titkosított biztonsági mentéssel.
- Online keresés cím vagy szerző alapján, valamint kézi könyvfelvétel és szerkesztés.
- Olvasási állapotok, oldalszám-követés, saját értékelés, közösségi átlag megjelenítése és jegyzetelés.
- Olvasási statisztikák, éves kihívás, állapot szerinti megoszlás és havi gyarapodási grafikon.

## Futtatás és fordítás

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

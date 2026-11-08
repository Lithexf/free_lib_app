/// ISBN-10 és ISBN-13 ellenőrző és átalakító segédosztály.
///
/// Ellenőrzi az ellenőrző számjegyet (checksum), hogy a beolvasott vonalkódok
/// valódi ISBN számok legyenek az API hívások előtt. Kezeli az EAN-13 könyv-vonalkódokat
/// és rugalmas normalizálást biztosít a kopott vagy sérült vonalkódokhoz is.
class IsbnValidator {
  IsbnValidator._();

  /// Igazat ad vissza, ha a megadott karakterlánc érvényes ISBN (10 vagy 13 számjegyű).
  static bool isValid(String isbn) {
    final cleaned = isbn.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (cleaned.length == 10) return _isValidIsbn10(cleaned);
    if (cleaned.length == 13) return _isValidIsbn13(cleaned);
    return false;
  }

  /// Igazat ad vissza, ha a karakterlánc könyv-vonalkódnak tűnik.
  /// Megengedőbb, mint az [isValid] — elfogadja a 978/979 előtagú EAN-13 kódokat
  /// akkor is, ha az ellenőrző számjegy sérült (gyakori a kopott vonalkódoknál).
  static bool isLikelyBookBarcode(String code) {
    final cleaned = code.replaceAll(RegExp(r'[^0-9Xx]'), '');

    // Szabványos ISBN-10 vagy ISBN-13 érvényes ellenőrző összeggel
    if (isValid(cleaned)) return true;

    // 978-cal vagy 979-cel kezdődő EAN-13 (könyv-vonalkód előtag),
    // még ha az ellenőrző összeg kissé eltér is (sérült vonalkód)
    if (cleaned.length == 13 &&
        (cleaned.startsWith('978') || cleaned.startsWith('979'))) {
      return true;
    }

    // 10 jegyű karakterlánc, amely ISBN-10 lehet (megengedő ellenőrzés)
    if (cleaned.length == 10) {
      final body = cleaned.substring(0, 9);
      if (RegExp(r'^[0-9]+$').hasMatch(body)) return true;
    }

    return false;
  }

  /// ISBN normalizálása: kötőjelek és szóközök eltávolítása, majd ellenőrzés.
  /// Érvénytelen bemenet esetén `null` értéket ad vissza.
  ///
  /// Megengedő módot használ: elfogadja a valószínű könyv-vonalkódokat kisebb
  /// ellenőrzőösszeg-hibák esetén is (kopott/sérült vonalkódok).
  static String? normalize(String isbn) {
    final cleaned = isbn.replaceAll(RegExp(r'[^0-9Xx]'), '');

    // Elsőként szigorú ellenőrzés
    if (isValid(cleaned)) return cleaned;

    // Megengedő mód: 978/979-es EAN-13 könyv-vonalkódok elfogadása hibás ellenőrző összeggel is
    if (cleaned.length == 13 &&
        (cleaned.startsWith('978') || cleaned.startsWith('979'))) {
      return cleaned;
    }

    return null;
  }

  /// ISBN-10 átalakítása ISBN-13 formátumra.
  static String? isbn10to13(String isbn10) {
    final cleaned = isbn10.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (cleaned.length != 10) return null;

    final body = cleaned.substring(0, 9);
    for (int i = 0; i < 9; i++) {
      final code = body.codeUnitAt(i);
      if (code < 48 || code > 57) return null;
    }

    final base = '978$body';
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      final digit = base.codeUnitAt(i) - 48;
      sum += (i.isEven) ? digit : digit * 3;
    }
    final checkDigit = (10 - (sum % 10)) % 10;
    return '$base$checkDigit';
  }

  /// ISBN-13 átalakítása ISBN-10 formátumra (csak 978-as előtagú ISBN-eknél működik).
  /// 979-es előtagú ISBN esetén `null` értéket ad vissza (nincs ISBN-10 megfelelője).
  static String? isbn13to10(String isbn13) {
    final cleaned = isbn13.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.length != 13) return null;
    if (!cleaned.startsWith('978')) return null; // A 979-es előtagnak nincs ISBN-10 alakja

    final body = cleaned.substring(3, 12); // A 978 utáni 9 számjegy
    int sum = 0;
    for (int i = 0; i < 9; i++) {
      sum += int.parse(body[i]) * (10 - i);
    }
    final remainder = (11 - (sum % 11)) % 11;
    final checkChar = remainder == 10 ? 'X' : '$remainder';
    return '$body$checkChar';
  }

  /// Egy ISBN összes formátumváltozatának (ISBN-10, ISBN-13 vagy mindkettő) lekérése.
  /// Segít maximalizálni az API-keresések találati arányát.
  static List<String> getAllFormats(String isbn) {
    if (isbn.startsWith('LOCAL-')) return <String>[isbn];

    final cleaned = isbn.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (cleaned.isEmpty) return const <String>[];
    final formats = <String>{cleaned};

    if (cleaned.length == 10) {
      final isbn13 = isbn10to13(cleaned);
      if (isbn13 != null) formats.add(isbn13);
    } else if (cleaned.length == 13) {
      final isbn10 = isbn13to10(cleaned);
      if (isbn10 != null) formats.add(isbn10);
    }

    return formats.toList();
  }

  /// ISBN-10 ellenőrző összeg vizsgálata.
  static bool _isValidIsbn10(String isbn) {
    int sum = 0;
    for (int i = 0; i < 9; i++) {
      final c = isbn.codeUnitAt(i);
      if (c < 48 || c > 57) return false;
      sum += (c - 48) * (10 - i);
    }

    // Az utolsó karakter lehet 'X' is (amely 10-et jelent)
    final lastChar = isbn[9].toUpperCase();
    if (lastChar == 'X') {
      sum += 10;
    } else if (lastChar.codeUnitAt(0) >= 48 && lastChar.codeUnitAt(0) <= 57) {
      sum += lastChar.codeUnitAt(0) - 48;
    } else {
      return false;
    }

    return sum % 11 == 0;
  }

  /// ISBN-13 ellenőrző összeg vizsgálata.
  static bool _isValidIsbn13(String isbn) {
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      final c = isbn.codeUnitAt(i);
      if (c < 48 || c > 57) return false;
      final digit = c - 48;
      sum += (i.isEven) ? digit : digit * 3;
    }

    final lastCode = isbn.codeUnitAt(12);
    if (lastCode < 48 || lastCode > 57) return false;
    final checkDigit = (10 - (sum % 10)) % 10;
    return (lastCode - 48) == checkDigit;
  }
}

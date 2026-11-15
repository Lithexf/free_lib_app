class IsbnValidator {
  IsbnValidator._();

  static String _cleanAndStripAddon(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();
    if ((cleaned.length == 15 || cleaned.length == 18) &&
        (cleaned.startsWith('978') || cleaned.startsWith('979')) &&
        RegExp(r'^[0-9]+$').hasMatch(cleaned)) {
      return cleaned.substring(0, 13);
    }
    return cleaned;
  }

  static bool isValid(String isbn) {
    final cleaned = _cleanAndStripAddon(isbn);
    if (cleaned.length == 10) return _isValidIsbn10(cleaned);
    if (cleaned.length == 13) return _isValidIsbn13(cleaned);
    return false;
  }

  static bool isLikelyBookBarcode(String code) {
    final cleaned = _cleanAndStripAddon(code);

    if (isValid(cleaned)) return true;

    if (cleaned.length == 13 &&
        (cleaned.startsWith('978') || cleaned.startsWith('979')) &&
        RegExp(r'^[0-9]{13}$').hasMatch(cleaned)) {
      return true;
    }

    if (cleaned.length == 10) {
      final body = cleaned.substring(0, 9);
      final last = cleaned[9];
      if (RegExp(r'^[0-9]{9}$').hasMatch(body) &&
          RegExp(r'^[0-9X]$').hasMatch(last)) {
        return true;
      }
    }

    return false;
  }

  static String? normalize(String isbn) {
    final cleaned = _cleanAndStripAddon(isbn);

    if (isValid(cleaned)) return cleaned;

    if (cleaned.length == 13 &&
        (cleaned.startsWith('978') || cleaned.startsWith('979')) &&
        RegExp(r'^[0-9]{13}$').hasMatch(cleaned)) {
      return cleaned;
    }

    return null;
  }

  static bool isHungarianIsbn(String isbn) {
    final cleaned = _cleanAndStripAddon(isbn);
    if (cleaned.length == 13) {
      return cleaned.startsWith('978963') || cleaned.startsWith('978615');
    }
    if (cleaned.length == 10) {
      return cleaned.startsWith('963') || cleaned.startsWith('615');
    }
    return false;
  }

  static String? isbn10to13(String isbn10) {
    final cleaned = _cleanAndStripAddon(isbn10);
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

  static String? isbn13to10(String isbn13) {
    final cleaned = _cleanAndStripAddon(isbn13);
    if (cleaned.length != 13) return null;
    if (!cleaned.startsWith('978')) return null;

    final body = cleaned.substring(3, 12);
    for (int i = 0; i < 9; i++) {
      final code = body.codeUnitAt(i);
      if (code < 48 || code > 57) return null;
    }

    int sum = 0;
    for (int i = 0; i < 9; i++) {
      sum += int.parse(body[i]) * (10 - i);
    }
    final remainder = (11 - (sum % 11)) % 11;
    final checkChar = remainder == 10 ? 'X' : '$remainder';
    return '$body$checkChar';
  }

  static List<String> getAllFormats(String isbn) {
    if (isbn.startsWith('LOCAL-')) return <String>[isbn];

    final cleaned = _cleanAndStripAddon(isbn);
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

  static bool _isValidIsbn10(String isbn) {
    int sum = 0;
    for (int i = 0; i < 9; i++) {
      final c = isbn.codeUnitAt(i);
      if (c < 48 || c > 57) return false;
      sum += (c - 48) * (10 - i);
    }

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

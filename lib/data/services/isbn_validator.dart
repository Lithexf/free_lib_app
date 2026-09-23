/// ISBN-10 and ISBN-13 validation and conversion utility.
///
/// Validates checksum digits to ensure scanned barcodes are real ISBNs
/// before making API calls. Also handles EAN-13 book barcodes and
/// provides flexible normalization for damaged/partial scans.
class IsbnValidator {
  IsbnValidator._();

  /// Returns true if the given string is a valid ISBN (10 or 13 digits).
  static bool isValid(String isbn) {
    final cleaned = isbn.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (cleaned.length == 10) return _isValidIsbn10(cleaned);
    if (cleaned.length == 13) return _isValidIsbn13(cleaned);
    return false;
  }

  /// Returns true if the string looks like it could be a book barcode.
  /// More lenient than [isValid] — accepts EAN-13 barcodes with 978/979
  /// prefix even if checksum is damaged (common with worn barcodes).
  static bool isLikelyBookBarcode(String code) {
    final cleaned = code.replaceAll(RegExp(r'[^0-9Xx]'), '');

    // Standard ISBN-10 or ISBN-13 with valid checksum
    if (isValid(cleaned)) return true;

    // EAN-13 starting with 978 or 979 (book barcode prefix)
    // even if checksum is slightly off (damaged barcode)
    if (cleaned.length == 13 &&
        (cleaned.startsWith('978') || cleaned.startsWith('979'))) {
      return true;
    }

    // 10-digit string that could be ISBN-10 (lenient)
    if (cleaned.length == 10) {
      final body = cleaned.substring(0, 9);
      if (RegExp(r'^[0-9]+$').hasMatch(body)) return true;
    }

    return false;
  }

  /// Normalize an ISBN: strip hyphens/spaces, validate.
  /// Returns null if invalid.
  ///
  /// Uses lenient mode: accepts likely book barcodes even with
  /// minor checksum errors from damaged/worn barcodes.
  static String? normalize(String isbn) {
    final cleaned = isbn.replaceAll(RegExp(r'[^0-9Xx]'), '');

    // Strict validation first
    if (isValid(cleaned)) return cleaned;

    // Lenient: accept EAN-13 book barcodes (978/979) even with bad checksum
    if (cleaned.length == 13 &&
        (cleaned.startsWith('978') || cleaned.startsWith('979'))) {
      return cleaned;
    }

    return null;
  }

  /// Convert ISBN-10 to ISBN-13.
  static String? isbn10to13(String isbn10) {
    final cleaned = isbn10.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (cleaned.length != 10) return null;

    final base = '978${cleaned.substring(0, 9)}';
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      final digit = int.parse(base[i]);
      sum += (i.isEven) ? digit : digit * 3;
    }
    final checkDigit = (10 - (sum % 10)) % 10;
    return '$base$checkDigit';
  }

  /// Convert ISBN-13 to ISBN-10 (only works for 978-prefixed ISBNs).
  /// Returns null for 979-prefixed ISBNs (no ISBN-10 equivalent).
  static String? isbn13to10(String isbn13) {
    final cleaned = isbn13.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.length != 13) return null;
    if (!cleaned.startsWith('978')) return null; // 979 has no ISBN-10 form

    final body = cleaned.substring(3, 12); // 9 digits after 978
    int sum = 0;
    for (int i = 0; i < 9; i++) {
      sum += int.parse(body[i]) * (10 - i);
    }
    final remainder = (11 - (sum % 11)) % 11;
    final checkChar = remainder == 10 ? 'X' : '$remainder';
    return '$body$checkChar';
  }

  /// Get all format variants for an ISBN (ISBN-10, ISBN-13, or both).
  /// Useful for maximizing API lookup coverage.
  static List<String> getAllFormats(String isbn) {
    final cleaned = isbn.replaceAll(RegExp(r'[^0-9Xx]'), '');
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

  /// Validate ISBN-10 checksum.
  static bool _isValidIsbn10(String isbn) {
    int sum = 0;
    for (int i = 0; i < 9; i++) {
      final c = isbn[i];
      if (c.codeUnitAt(0) < 48 || c.codeUnitAt(0) > 57) return false;
      sum += int.parse(c) * (10 - i);
    }

    // Last character can be 'X' (representing 10)
    final lastChar = isbn[9].toUpperCase();
    if (lastChar == 'X') {
      sum += 10;
    } else if (lastChar.codeUnitAt(0) >= 48 && lastChar.codeUnitAt(0) <= 57) {
      sum += int.parse(lastChar);
    } else {
      return false;
    }

    return sum % 11 == 0;
  }

  /// Validate ISBN-13 checksum.
  static bool _isValidIsbn13(String isbn) {
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      final c = isbn[i];
      if (c.codeUnitAt(0) < 48 || c.codeUnitAt(0) > 57) return false;
      final digit = int.parse(c);
      sum += (i.isEven) ? digit : digit * 3;
    }

    final checkDigit = (10 - (sum % 10)) % 10;
    return int.parse(isbn[12]) == checkDigit;
  }
}

/// ISBN-10 and ISBN-13 validation utility.
///
/// Validates checksum digits to ensure scanned barcodes are real ISBNs
/// before making API calls.
class IsbnValidator {
  IsbnValidator._();

  /// Returns true if the given string is a valid ISBN (10 or 13 digits).
  static bool isValid(String isbn) {
    final cleaned = isbn.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (cleaned.length == 10) return _isValidIsbn10(cleaned);
    if (cleaned.length == 13) return _isValidIsbn13(cleaned);
    return false;
  }

  /// Normalize an ISBN: strip hyphens/spaces, validate.
  /// Returns null if invalid.
  static String? normalize(String isbn) {
    final cleaned = isbn.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (isValid(cleaned)) return cleaned;
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

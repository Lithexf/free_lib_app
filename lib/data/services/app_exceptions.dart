/// Base exception type for domain and infrastructure errors in FreeLib.
sealed class AppException implements Exception {
  final String userMessage;
  final Object? cause;

  const AppException(this.userMessage, {this.cause});

  @override
  String toString() => userMessage;
}

/// Thrown when an external API call fails due to missing internet connection,
/// DNS failure, or timeout.
class NetworkException extends AppException {
  const NetworkException([
    super.userMessage =
        'Hálózati hiba történt. Ellenőrizd az internetkapcsolatot, vagy add hozzá a könyvet manuálisan.',
    Object? cause,
  ]) : super(cause: cause);
}

/// Thrown when an external service returns an unexpected error response.
class ApiLookupException extends AppException {
  const ApiLookupException([
    super.userMessage =
        'A külső könyvadatbázis jelenleg nem érhető el. Próbáld újra később, vagy add meg az adatokat kézzel.',
    Object? cause,
  ]) : super(cause: cause);
}

/// Thrown when attempting to insert a book whose ISBN is already in the library.
class DuplicateBookException extends AppException {
  final String isbn;
  final String existingTitle;

  DuplicateBookException({
    required this.isbn,
    required this.existingTitle,
  }) : super('A(z) „$existingTitle” (ISBN: $isbn) már szerepel a könyvtáradban.');
}

/// Thrown when a local SQLite database operation fails.
class StorageException extends AppException {
  const StorageException([
    super.userMessage = 'Adatbázis hiba történt a művelet közben.',
    Object? cause,
  ]) : super(cause: cause);
}


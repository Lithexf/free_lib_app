sealed class AppException implements Exception {
  final String userMessage;
  final Object? cause;

  const AppException(this.userMessage, {this.cause});

  @override
  String toString() => userMessage;
}

class NetworkException extends AppException {
  const NetworkException([
    super.userMessage =
        'Hálózati hiba történt. Ellenőrizd az internetkapcsolatot, vagy add hozzá a könyvet manuálisan.',
    Object? cause,
  ]) : super(cause: cause);
}

class ApiLookupException extends AppException {
  const ApiLookupException([
    super.userMessage =
        'A külső könyvadatbázis jelenleg nem érhető el. Próbáld újra később, vagy add meg az adatokat kézzel.',
    Object? cause,
  ]) : super(cause: cause);
}

class DuplicateBookException extends AppException {
  final String isbn;
  final String existingTitle;

  DuplicateBookException({
    required this.isbn,
    required this.existingTitle,
  }) : super('A(z) "$existingTitle" (ISBN: $isbn) már szerepel a könyvtáradban.');
}

class StorageException extends AppException {
  const StorageException([
    super.userMessage = 'Adatbázis hiba történt a művelet közben.',
    Object? cause,
  ]) : super(cause: cause);
}

/// Alap kivételosztály a FreeLib alkalmazás üzleti és infrastrukturális hibáihoz.
sealed class AppException implements Exception {
  final String userMessage;
  final Object? cause;

  const AppException(this.userMessage, {this.cause});

  @override
  String toString() => userMessage;
}

/// Akkor keletkezik, ha egy külső API hívás hiányzó internetkapcsolat,
/// DNS-hiba vagy időtúllépés miatt meghiúsul.
class NetworkException extends AppException {
  const NetworkException([
    super.userMessage =
        'Hálózati hiba történt. Ellenőrizd az internetkapcsolatot, vagy add hozzá a könyvet manuálisan.',
    Object? cause,
  ]) : super(cause: cause);
}

/// Akkor keletkezik, ha egy külső szolgáltatás váratlan hibaválaszt ad vissza.
class ApiLookupException extends AppException {
  const ApiLookupException([
    super.userMessage =
        'A külső könyvadatbázis jelenleg nem érhető el. Próbáld újra később, vagy add meg az adatokat kézzel.',
    Object? cause,
  ]) : super(cause: cause);
}

/// Akkor keletkezik, ha olyan könyvet próbálunk beszúrni, amelynek ISBN száma már szerepel a könyvtárban.
class DuplicateBookException extends AppException {
  final String isbn;
  final String existingTitle;

  DuplicateBookException({
    required this.isbn,
    required this.existingTitle,
  }) : super('A(z) „$existingTitle” (ISBN: $isbn) már szerepel a könyvtáradban.');
}

/// Akkor keletkezik, ha egy helyi SQLite adatbázis-művelet meghiúsul.
class StorageException extends AppException {
  const StorageException([
    super.userMessage = 'Adatbázis hiba történt a művelet közben.',
    Object? cause,
  ]) : super(cause: cause);
}

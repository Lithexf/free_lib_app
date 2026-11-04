import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database/app_database.dart';
import '../data/services/book_api_service.dart';

/// Egyke (Singleton) helyi adatbázis szolgáltató (provider)
final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase.instance;
});

/// Könyv API szolgáltató (provider)
final bookApiServiceProvider = Provider<BookApiService>((ref) {
  return BookApiService();
});

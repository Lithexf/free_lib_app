import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database/app_database.dart';
import '../data/services/book_api_service.dart';

/// Singleton database provider
final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase.instance;
});

/// Book API service provider
final bookApiServiceProvider = Provider<BookApiService>((ref) {
  return BookApiService();
});

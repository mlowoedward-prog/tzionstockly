import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'app_database.dart';
import 'database_service.dart';
import '../../features/stock/domain/stock_service.dart';
import '../../features/products/domain/product_stock_info.dart';
import '../../features/reports/domain/reports_service.dart';
import '../utils/export_service.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final executor = driftDatabase(name: 'tzion_stockly');
  final db = AppDatabase(executor);
  ref.onDispose(() => db.close());
  return db;
});

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return DatabaseService(db);
});

final stockServiceProvider = Provider<StockService>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  return StockService(dbService: dbService);
});

final reportsServiceProvider = Provider<ReportsService>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  return ReportsService(dbService);
});

final exportServiceProvider = Provider<ExportService>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  return ExportService(dbService);
});

final currentBusinessIdProvider = StateProvider<String>((ref) {
  return DatabaseService.defaultBusinessId;
});

final searchQueryProvider = StateProvider<String>((ref) => '');
final selectedCategoryFilterProvider = StateProvider<String?>((ref) => null);

final productsStreamProvider = StreamProvider.autoDispose<List<ProductStockInfo>>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  final bizId = ref.watch(currentBusinessIdProvider);
  final search = ref.watch(searchQueryProvider);
  final categoryId = ref.watch(selectedCategoryFilterProvider);

  return dbService.watchProductsWithStock(bizId, search: search, categoryId: categoryId);
});

final categoriesStreamProvider = StreamProvider.autoDispose<List<Category>>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  final bizId = ref.watch(currentBusinessIdProvider);
  return dbService.watchCategories(bizId);
});

final partnersStreamProvider = StreamProvider.autoDispose.family<List<Partner>, String?>((ref, type) {
  final dbService = ref.watch(databaseServiceProvider);
  final bizId = ref.watch(currentBusinessIdProvider);
  return dbService.watchPartners(bizId, type: type);
});

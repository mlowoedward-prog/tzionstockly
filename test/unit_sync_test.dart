import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:tzion_stockly/core/database/app_database.dart';
import 'package:tzion_stockly/core/database/database_service.dart';
import 'package:tzion_stockly/core/sync/sync_models.dart';

void main() {
  late AppDatabase db;
  late DatabaseService dbService;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dbService = DatabaseService(db);
    await dbService.ensureDefaultBusiness();
  });

  tearDown(() async {
    await db.close();
  });

  group('Sync & Data Adoption Tests', () {
    test('Creating items adds records to sync_queue with correct operation', () async {
      final category = await dbService.createCategory(
        businessId: DatabaseService.defaultBusinessId,
        name: 'Vinywaji',
      );

      final queueCount = await dbService.getSyncQueueCount();
      expect(queueCount, equals(1));

      final product = await dbService.createProduct(
        businessId: DatabaseService.defaultBusinessId,
        name: 'Kilimanjaro Premium Lager',
        unit: 'Boti',
        costPrice: 2000,
        sellingPrice: 3000,
        reorderLevel: 24,
        categoryId: category.id,
        openingQuantity: 48,
      );

      // 1 for category, 1 for product, 1 for opening stock movement
      final updatedQueueCount = await dbService.getSyncQueueCount();
      expect(updatedQueueCount, equals(3));
      expect(product.name, equals('Kilimanjaro Premium Lager'));
    });

    test('adoptDefaultBusinessData re-assigns all offline records to new businessId', () async {
      final cat = await dbService.createCategory(
        businessId: DatabaseService.defaultBusinessId,
        name: 'Vyakula',
      );

      final prod = await dbService.createProduct(
        businessId: DatabaseService.defaultBusinessId,
        name: 'Mchele wa Mbeya 1kg',
        unit: 'Kg',
        costPrice: 2200,
        sellingPrice: 2800,
        reorderLevel: 10,
        categoryId: cat.id,
        openingQuantity: 50,
      );

      const newBizId = '11111111-2222-3333-4444-555555555555';
      await dbService.adoptDefaultBusinessData(newBizId);

      final adoptedProd = await dbService.getProductStockInfo(prod.id);
      expect(adoptedProd?.businessId, equals(newBizId));

      final categories = await dbService.getCategories(newBizId);
      expect(categories.length, equals(1));
      expect(categories.first.name, equals('Vyakula'));
    });

    test('SyncStatusInfo state immutability and defaults', () {
      const status = SyncStatusInfo(
        state: RealSyncState.pending,
        pendingCount: 5,
      );

      expect(status.state, equals(RealSyncState.pending));
      expect(status.pendingCount, equals(5));
      expect(status.lastSyncedAt, isNull);
    });
  });
}

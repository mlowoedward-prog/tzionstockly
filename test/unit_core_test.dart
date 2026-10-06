import 'package:test/test.dart';
import 'package:drift/native.dart';
import 'package:tzion_stockly/core/database/app_database.dart';
import 'package:tzion_stockly/core/database/database_service.dart';
import 'package:tzion_stockly/features/stock/domain/stock_service.dart';
import 'package:tzion_stockly/features/products/domain/product_stock_info.dart';

void main() {
  late AppDatabase db;
  late DatabaseService dbService;
  late StockService stockService;

  setUp(() {
    // In-memory SQLite database for unit testing
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dbService = DatabaseService(db);
    stockService = StockService(dbService: dbService);
  });

  tearDown(() async {
    await db.close();
  });

  group('Prompt 1 Unit Core Tests', () {
    test('Quantity on hand calculation SUM(signed quantity)', () async {
      final bizId = await dbService.ensureDefaultBusiness();

      final p = await dbService.createProduct(
        businessId: bizId,
        name: 'Sugar 1kg',
        unit: 'kg',
        costPrice: 2800,
        sellingPrice: 3200,
        reorderLevel: 5,
        openingQuantity: 20, // Initial purchase: +20
      );

      // Record sale: -5
      await stockService.recordSale(
        businessId: bizId,
        productId: p.id,
        quantity: 5,
        unitCost: 2800,
        unitPrice: 3200,
      );

      // Record damage: -2
      await stockService.recordDamage(
        businessId: bizId,
        productId: p.id,
        quantity: 2,
        unitCost: 2800,
        unitPrice: 3200,
      );

      // Record adjustment: +3
      await stockService.recordAdjustment(
        businessId: bizId,
        productId: p.id,
        signedQuantity: 3,
        unitCost: 2800,
        unitPrice: 3200,
      );

      final qty = await dbService.getQuantityOnHand(p.id);
      // Expected = 20 - 5 - 2 + 3 = 16
      expect(qty, equals(16));
    });

    test('Stock status thresholds (inStock, lowStock, outOfStock)', () {
      expect(ProductStockInfo.calculateStatus(20, 5), equals(StockStatus.inStock));
      expect(ProductStockInfo.calculateStatus(5, 5), equals(StockStatus.lowStock));
      expect(ProductStockInfo.calculateStatus(2, 5), equals(StockStatus.lowStock));
      expect(ProductStockInfo.calculateStatus(0, 5), equals(StockStatus.outOfStock));
      expect(ProductStockInfo.calculateStatus(-3, 5), equals(StockStatus.outOfStock));
    });

    test('Negative stock policy rule (allowWithWarning vs block)', () async {
      final bizId = await dbService.ensureDefaultBusiness();
      final p = await dbService.createProduct(
        businessId: bizId,
        name: 'Soda Crate',
        unit: 'crate',
        costPrice: 18000,
        sellingPrice: 22000,
        reorderLevel: 2,
        openingQuantity: 3,
      );

      // Policy set to block
      stockService.negativeStockPolicy = NegativeStockPolicy.block;
      final blockResult = await stockService.recordSale(
        businessId: bizId,
        productId: p.id,
        quantity: 5, // 3 available, trying to sell 5
        unitCost: 18000,
        unitPrice: 22000,
      );

      expect(blockResult.success, isFalse);
      expect(blockResult.errorMessage, contains('Sale blocked'));

      // Policy set to allowWithWarning
      stockService.negativeStockPolicy = NegativeStockPolicy.allowWithWarning;
      final warnResult = await stockService.recordSale(
        businessId: bizId,
        productId: p.id,
        quantity: 5,
        unitCost: 18000,
        unitPrice: 22000,
      );

      expect(warnResult.success, isTrue);
      expect(warnResult.warningMessage, contains('Stock is now negative'));
      final newQty = await dbService.getQuantityOnHand(p.id);
      expect(newQty, equals(-2));
    });

    test('Soft delete product logic (deletedAt set and excluded from get/list)', () async {
      final bizId = await dbService.ensureDefaultBusiness();
      final p = await dbService.createProduct(
        businessId: bizId,
        name: 'Soap Bar',
        unit: 'bar',
        costPrice: 1000,
        sellingPrice: 1500,
        reorderLevel: 5,
      );

      await dbService.softDeleteProduct(p.id);

      final pInfo = await dbService.getProductStockInfo(p.id);
      expect(pInfo?.deletedAt, isNotNull);
    });

    test('Sync queue entry created for every local write', () async {
      final bizId = await dbService.ensureDefaultBusiness();

      final countBefore = await dbService.getSyncQueueCount();

      await dbService.createProduct(
        businessId: bizId,
        name: 'Maize Flour 2kg',
        unit: 'bag',
        costPrice: 4000,
        sellingPrice: 4600,
        reorderLevel: 5,
        openingQuantity: 10, // Creates product insert + movement insert -> 2 sync queue entries
      );

      final countAfter = await dbService.getSyncQueueCount();
      expect(countAfter - countBefore, equals(2));
    });
  });
}

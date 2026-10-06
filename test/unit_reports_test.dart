import 'package:test/test.dart';
import 'package:drift/native.dart';
import 'package:tzion_stockly/core/database/app_database.dart';
import 'package:tzion_stockly/core/database/database_service.dart';
import 'package:tzion_stockly/features/stock/domain/stock_service.dart';
import 'package:tzion_stockly/features/reports/domain/reports_service.dart';

void main() {
  late AppDatabase db;
  late DatabaseService dbService;
  late StockService stockService;
  late ReportsService reportsService;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dbService = DatabaseService(db);
    stockService = StockService(dbService: dbService);
    reportsService = ReportsService(dbService);
  });

  tearDown(() async {
    await db.close();
  });

  group('Prompt 2 Reports & Analytics Unit Tests', () {
    test('Gross Profit calculation (Sales Revenue minus COGS)', () async {
      final bizId = await dbService.ensureDefaultBusiness();

      final p = await dbService.createProduct(
        businessId: bizId,
        name: 'Rice 25kg',
        unit: 'bag',
        costPrice: 75000,
        sellingPrice: 85000,
        reorderLevel: 5,
        openingQuantity: 50,
      );

      // Record 3 sales of Rice 25kg at 85,000 TZS (cost 75,000 TZS)
      await stockService.recordSale(
        businessId: bizId,
        productId: p.id,
        quantity: 3,
        unitCost: 75000,
        unitPrice: 85000,
      );

      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));

      final report = await reportsService.getSalesSummary(
        businessId: bizId,
        startDate: start,
        endDate: end,
      );

      // Expected Revenue = 3 * 85000 = 255,000
      // Expected COGS = 3 * 75000 = 225,000
      // Expected Gross Profit = 30,000
      expect(report.totalSalesRevenue, equals(255000));
      expect(report.totalCostOfGoodsSold, equals(225000));
      expect(report.grossProfit, equals(30000));
      expect(report.grossProfitMargin, closeTo(11.76, 0.05));
    });

    test('Edge Case: Returns, Adjustments & Archived Products', () async {
      final bizId = await dbService.ensureDefaultBusiness();

      final p = await dbService.createProduct(
        businessId: bizId,
        name: 'Sugar 1kg',
        unit: 'kg',
        costPrice: 2800,
        sellingPrice: 3200,
        reorderLevel: 5,
        openingQuantity: 10,
      );

      // Record sale: 2
      await stockService.recordSale(
        businessId: bizId,
        productId: p.id,
        quantity: 2,
        unitCost: 2800,
        unitPrice: 3200,
      );

      // Record return: 1 (should NOT be counted as sale revenue in sales summary)
      await stockService.recordReturn(
        businessId: bizId,
        productId: p.id,
        quantity: 1,
        unitCost: 2800,
        unitPrice: 3200,
      );

      // Soft delete product mid-period
      await dbService.softDeleteProduct(p.id);

      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));

      final report = await reportsService.getSalesSummary(
        businessId: bizId,
        startDate: start,
        endDate: end,
      );

      // Historical sales log still accounts for recorded sales
      expect(report.totalSalesRevenue, equals(6400));
      expect(report.totalItemsSold, equals(2));
    });

    test('Performance Benchmark: Aggregations load in under 2 seconds', () async {
      final bizId = await dbService.ensureDefaultBusiness();

      final stopwatch = Stopwatch()..start();

      // Seed test dataset
      final p = await dbService.createProduct(
        businessId: bizId,
        name: 'Benchmark Item',
        unit: 'pcs',
        costPrice: 1000,
        sellingPrice: 1500,
        reorderLevel: 10,
      );

      for (int i = 0; i < 50; i++) {
        await stockService.recordSale(
          businessId: bizId,
          productId: p.id,
          quantity: 1,
          unitCost: 1000,
          unitPrice: 1500,
        );
      }

      final startQuery = stopwatch.elapsedMilliseconds;
      await reportsService.getDashboardKpis(bizId);
      final now = DateTime.now();
      await reportsService.getSalesSummary(
        businessId: bizId,
        startDate: DateTime(now.year, now.month, 1),
        endDate: DateTime(now.year, now.month + 1, 1),
      );
      await reportsService.getStockValuationReport(bizId);
      final totalQueryTime = stopwatch.elapsedMilliseconds - startQuery;

      stopwatch.stop();
      print('Performance Benchmark Query Time: ${totalQueryTime}ms');

      // Assert total report query execution time is well under 2,000 ms (2 seconds)
      expect(totalQueryTime, lessThan(2000));
    });
  });
}

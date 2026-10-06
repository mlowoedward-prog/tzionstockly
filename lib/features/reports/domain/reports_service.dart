import 'package:drift/drift.dart';
import '../../products/domain/product_stock_info.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_service.dart';

class DailySalesData {
  final DateTime date;
  final int totalSales;

  DailySalesData({required this.date, required this.totalSales});
}

class TopProductSalesData {
  final String productId;
  final String productName;
  final int totalQuantitySold;
  final int totalRevenue;

  TopProductSalesData({
    required this.productId,
    required this.productName,
    required this.totalQuantitySold,
    required this.totalRevenue,
  });
}

class SalesSummaryReport {
  final DateTime startDate;
  final DateTime endDate;
  final int totalSalesRevenue;
  final int totalCostOfGoodsSold;
  final int grossProfit;
  final double grossProfitMargin;
  final int totalItemsSold;

  SalesSummaryReport({
    required this.startDate,
    required this.endDate,
    required this.totalSalesRevenue,
    required this.totalCostOfGoodsSold,
    required this.grossProfit,
    required this.grossProfitMargin,
    required this.totalItemsSold,
  });
}

class StockValuationItem {
  final String productId;
  final String productName;
  final String? categoryName;
  final int quantityOnHand;
  final int costPrice;
  final int sellingPrice;
  final int totalCostValuation;
  final int totalRetailValuation;

  StockValuationItem({
    required this.productId,
    required this.productName,
    this.categoryName,
    required this.quantityOnHand,
    required this.costPrice,
    required this.sellingPrice,
    required this.totalCostValuation,
    required this.totalRetailValuation,
  });
}

class ReportsService {
  final DatabaseService dbService;

  ReportsService(this.dbService);

  AppDatabase get db => dbService.db;

  /// Get Dashboard Overview KPIs
  Future<Map<String, dynamic>> getDashboardKpis(String businessId) async {
    final products = await dbService.watchProductsWithStock(businessId).first;

    int totalStockCostValue = 0;
    int lowStockCount = 0;
    int outOfStockCount = 0;

    for (final p in products) {
      if (p.quantityOnHand > 0) {
        totalStockCostValue += p.quantityOnHand * p.costPrice;
      }
      if (p.status == StockStatus.lowStock) {
        lowStockCount++;
      } else if (p.status == StockStatus.outOfStock) {
        outOfStockCount++;
      }
    }

    // Sales today
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final salesTodaySummary = await getSalesSummary(
      businessId: businessId,
      startDate: startOfDay,
      endDate: endOfDay,
    );

    return {
      'totalStockValue': totalStockCostValue,
      'salesToday': salesTodaySummary.totalSalesRevenue,
      'lowStockCount': lowStockCount,
      'outOfStockCount': outOfStockCount,
    };
  }

  /// Get Sales summary & Gross profit for a date range using SQL aggregates
  Future<SalesSummaryReport> getSalesSummary({
    required String businessId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final query = db.select(db.stockMovements)
      ..where((m) =>
          m.businessId.equals(businessId) &
          m.type.equals('sale') &
          m.occurredAt.isBiggerOrEqualValue(startDate) &
          m.occurredAt.isSmallerThanValue(endDate) &
          m.deletedAt.isNull());

    final movements = await query.get();

    int totalRevenue = 0;
    int totalCogs = 0;
    int totalItems = 0;

    for (final m in movements) {
      final qty = m.quantity.abs();
      totalRevenue += qty * m.unitPrice;
      totalCogs += qty * m.unitCost;
      totalItems += qty;
    }

    final grossProfit = totalRevenue - totalCogs;
    final margin = totalRevenue > 0 ? (grossProfit / totalRevenue) * 100 : 0.0;

    return SalesSummaryReport(
      startDate: startDate,
      endDate: endDate,
      totalSalesRevenue: totalRevenue,
      totalCostOfGoodsSold: totalCogs,
      grossProfit: grossProfit,
      grossProfitMargin: margin,
      totalItemsSold: totalItems,
    );
  }

  /// Get Sales trend for last N days (for Line Chart)
  Future<List<DailySalesData>> getSalesLastNDays(String businessId, {int days = 7}) async {
    final now = DateTime.now();
    final result = <DailySalesData>[];

    for (int i = days - 1; i >= 0; i--) {
      final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final nextDay = day.add(const Duration(days: 1));

      final summary = await getSalesSummary(
        businessId: businessId,
        startDate: day,
        endDate: nextDay,
      );

      result.add(DailySalesData(date: day, totalSales: summary.totalSalesRevenue));
    }
    return result;
  }

  /// Get Top products by quantity sold
  Future<List<TopProductSalesData>> getTopProductsThisMonth(String businessId, {int limit = 5}) async {
    final now = DateTime.now();
    final firstOfMonth = DateTime(now.year, now.month, 1);
    final nextMonth = DateTime(now.year, now.month + 1, 1);

    final movements = await (db.select(db.stockMovements)
          ..where((m) =>
              m.businessId.equals(businessId) &
              m.type.equals('sale') &
              m.occurredAt.isBiggerOrEqualValue(firstOfMonth) &
              m.occurredAt.isSmallerThanValue(nextMonth) &
              m.deletedAt.isNull()))
        .get();

    final Map<String, int> qtyMap = {};
    final Map<String, int> revMap = {};

    for (final m in movements) {
      final qty = m.quantity.abs();
      qtyMap[m.productId] = (qtyMap[m.productId] ?? 0) + qty;
      revMap[m.productId] = (revMap[m.productId] ?? 0) + (qty * m.unitPrice);
    }

    final sortedKeys = qtyMap.keys.toList()
      ..sort((a, b) => qtyMap[b]!.compareTo(qtyMap[a]!));

    final topKeys = sortedKeys.take(limit).toList();

    final result = <TopProductSalesData>[];
    for (final key in topKeys) {
      final pInfo = await dbService.getProductStockInfo(key);
      if (pInfo != null) {
        result.add(
          TopProductSalesData(
            productId: key,
            productName: pInfo.name,
            totalQuantitySold: qtyMap[key]!,
            totalRevenue: revMap[key]!,
          ),
        );
      }
    }
    return result;
  }

  /// Stock Valuation report by product and category
  Future<List<StockValuationItem>> getStockValuationReport(String businessId) async {
    final products = await dbService.watchProductsWithStock(businessId).first;
    final result = <StockValuationItem>[];

    for (final p in products) {
      final qty = p.quantityOnHand > 0 ? p.quantityOnHand : 0;
      result.add(
        StockValuationItem(
          productId: p.id,
          productName: p.name,
          categoryName: p.categoryName,
          quantityOnHand: p.quantityOnHand,
          costPrice: p.costPrice,
          sellingPrice: p.sellingPrice,
          totalCostValuation: qty * p.costPrice,
          totalRetailValuation: qty * p.sellingPrice,
        ),
      );
    }
    return result;
  }

  /// Slow movers: products with no sales in N days
  Future<List<ProductStockInfo>> getSlowMovers(String businessId, {int thresholdDays = 30}) async {
    final cutoffDate = DateTime.now().subtract(Duration(days: thresholdDays));
    final products = await dbService.watchProductsWithStock(businessId).first;

    final result = <ProductStockInfo>[];
    for (final p in products) {
      final recentSales = await (db.select(db.stockMovements)
            ..where((m) =>
                m.productId.equals(p.id) &
                m.type.equals('sale') &
                m.occurredAt.isBiggerOrEqualValue(cutoffDate) &
                m.deletedAt.isNull()))
          .get();
      if (recentSales.isEmpty) {
        result.add(p);
      }
    }
    return result;
  }
}

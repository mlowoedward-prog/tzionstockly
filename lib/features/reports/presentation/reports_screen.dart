import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/database/providers.dart';
import '../../products/domain/product_stock_info.dart';
import '../../auth/domain/role_permissions.dart';
import '../domain/reports_service.dart';

enum DateRangeFilter { today, week, month, custom }

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateRangeFilter _selectedRange = DateRangeFilter.month;
  final DateTime _customStartDate = DateTime.now().subtract(const Duration(days: 30));
  final DateTime _customEndDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  (DateTime, DateTime) _getEffectiveDateRange() {
    final now = DateTime.now();
    switch (_selectedRange) {
      case DateRangeFilter.today:
        final start = DateTime(now.year, now.month, now.day);
        return (start, start.add(const Duration(days: 1)));
      case DateRangeFilter.week:
        final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
        return (start, now);
      case DateRangeFilter.month:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 1);
        return (start, end);
      case DateRangeFilter.custom:
        return (_customStartDate, _customEndDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userRole = ref.watch(userRoleProvider);

    // Enforce Role-Based Access Control: Staff cannot view financial reports or margins
    if (!RolePermissions.canViewFinancialReports(userRole)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reports & Analysis')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_person_rounded, size: 72, color: Colors.amber),
                const SizedBox(height: 16),
                const Text(
                  'Access Restricted',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your current role (${userRole.toFormattedString()}) does not have clearance to view COGS, sales turnover, and profit margins. Please contact your shop owner.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final (startDate, endDate) = _getEffectiveDateRange();
    final dateRangeStr = '${DateFormat('MMM d, yyyy').format(startDate)} - ${DateFormat('MMM d, yyyy').format(endDate)}';
    final exportService = ref.watch(exportServiceProvider);
    final bizId = ref.watch(currentBusinessIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Analysis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Export PDF',
            onPressed: () async {
              final reportsService = ref.read(reportsServiceProvider);
              final sales = await reportsService.getSalesSummary(businessId: bizId, startDate: startDate, endDate: endDate);
              final currency = NumberFormat('#,##0', 'en_US');

              await exportService.exportPdfReport(
                reportTitle: 'Sales & Gross Profit Report',
                businessName: 'Tzion Stockly Shop',
                dateRangeText: dateRangeStr,
                headers: ['Metric', 'Amount (TZS)'],
                dataRows: [
                  ['Sales Revenue', 'TZS ${currency.format(sales.totalSalesRevenue)}'],
                  ['Cost of Goods Sold (COGS)', 'TZS ${currency.format(sales.totalCostOfGoodsSold)}'],
                  ['Gross Profit', 'TZS ${currency.format(sales.grossProfit)}'],
                  ['Gross Profit Margin', '${sales.grossProfitMargin.toStringAsFixed(1)}%'],
                  ['Items Sold', '${sales.totalItemsSold}'],
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Export CSV',
            onPressed: () async {
              final reportsService = ref.read(reportsServiceProvider);
              final sales = await reportsService.getSalesSummary(businessId: bizId, startDate: startDate, endDate: endDate);

              await exportService.exportCsv(
                fileNamePrefix: 'stockly_sales',
                rows: [
                  ['Metric', 'Amount'],
                  ['Sales Revenue', sales.totalSalesRevenue],
                  ['Cost of Goods Sold', sales.totalCostOfGoodsSold],
                  ['Gross Profit', sales.grossProfit],
                  ['Gross Profit Margin %', sales.grossProfitMargin.toStringAsFixed(2)],
                  ['Total Items Sold', sales.totalItemsSold],
                ],
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey.shade300,
          indicatorColor: const Color(0xFF14B8A6),
          tabs: const [
            Tab(text: 'Sales & Profit'),
            Tab(text: 'Stock Valuation'),
            Tab(text: 'Top Sellers'),
            Tab(text: 'Slow Movers'),
            Tab(text: 'Low Stock'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Filter Chips Row
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 18, color: Color(0xFF1F3864)),
                const SizedBox(width: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: DateRangeFilter.values.map((f) {
                      final isSelected = _selectedRange == f;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: ChoiceChip(
                          label: Text(f.name.toUpperCase()),
                          selected: isSelected,
                          onSelected: (_) => setState(() => _selectedRange = f),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _SalesProfitReportView(startDate: startDate, endDate: endDate),
                _StockValuationReportView(),
                _TopSellersReportView(limit: 10),
                _SlowMoversReportView(),
                _LowStockReportView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesProfitReportView extends ConsumerWidget {
  final DateTime startDate;
  final DateTime endDate;

  const _SalesProfitReportView({required this.startDate, required this.endDate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsService = ref.watch(reportsServiceProvider);
    final bizId = ref.watch(currentBusinessIdProvider);
    final currency = NumberFormat('#,##0', 'en_US');

    return FutureBuilder<SalesSummaryReport>(
      future: reportsService.getSalesSummary(businessId: bizId, startDate: startDate, endDate: endDate),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final sales = snapshot.data!;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _metricRow('Sales Revenue', 'TZS ${currency.format(sales.totalSalesRevenue)}', isBold: true),
                      const Divider(),
                      _metricRow('Cost of Goods Sold (COGS)', 'TZS ${currency.format(sales.totalCostOfGoodsSold)}'),
                      const Divider(),
                      _metricRow(
                        'Gross Profit',
                        'TZS ${currency.format(sales.grossProfit)}',
                        isBold: true,
                        valueColor: sales.grossProfit >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      ),
                      const Divider(),
                      _metricRow('Gross Profit Margin', '${sales.grossProfitMargin.toStringAsFixed(1)}%'),
                      const Divider(),
                      _metricRow('Total Items Sold', '${sales.totalItemsSold} pcs'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _metricRow(String title, String value, {bool isBold = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(fontSize: isBold ? 16 : 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(
            value,
            style: TextStyle(
              fontSize: isBold ? 18 : 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: valueColor ?? Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _StockValuationReportView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsService = ref.watch(reportsServiceProvider);
    final bizId = ref.watch(currentBusinessIdProvider);
    final currency = NumberFormat('#,##0', 'en_US');

    return FutureBuilder<List<StockValuationItem>>(
      future: reportsService.getStockValuationReport(bizId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final items = snapshot.data!;

        int totalCost = 0;
        int totalRetail = 0;
        for (final item in items) {
          totalCost += item.totalCostValuation;
          totalRetail += item.totalRetailValuation;
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: const Color(0xFF1F3864),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text('Cost Valuation', style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text('TZS ${currency.format(totalCost)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('Retail Valuation', style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text('TZS ${currency.format(totalRetail)}', style: const TextStyle(color: Color(0xFF14B8A6), fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  title: Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${item.categoryName ?? "General"} • ${item.quantityOnHand} in stock'),
                  trailing: Text('TZS ${currency.format(item.totalCostValuation)}'),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _TopSellersReportView extends ConsumerWidget {
  final int limit;

  const _TopSellersReportView({required this.limit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsService = ref.watch(reportsServiceProvider);
    final bizId = ref.watch(currentBusinessIdProvider);
    final currency = NumberFormat('#,##0', 'en_US');

    return FutureBuilder<List<TopProductSalesData>>(
      future: reportsService.getTopProductsThisMonth(bizId, limit: limit),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final items = snapshot.data!;
        if (items.isEmpty) return const Center(child: Text('No sales recorded this month.'));

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF14B8A6),
                child: Text('#${index + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              title: Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Sold: ${item.totalQuantitySold} pcs'),
              trailing: Text('TZS ${currency.format(item.totalRevenue)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            );
          },
        );
      },
    );
  }
}

class _SlowMoversReportView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsService = ref.watch(reportsServiceProvider);
    final bizId = ref.watch(currentBusinessIdProvider);

    return FutureBuilder<List<ProductStockInfo>>(
      future: reportsService.getSlowMovers(bizId, thresholdDays: 30),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final items = snapshot.data!;
        if (items.isEmpty) return const Center(child: Text('No slow movers detected in the last 30 days.'));

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              leading: const Icon(Icons.timer_off, color: Colors.orange),
              title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Stock: ${item.quantityOnHand} ${item.unit} • No sales in past 30 days'),
            );
          },
        );
      },
    );
  }
}

class _LowStockReportView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsStreamProvider);

    return productsAsync.when(
      data: (products) {
        final lowItems = products.where((p) => p.status != StockStatus.inStock).toList();
        if (lowItems.isEmpty) return const Center(child: Text('All products are well stocked.'));

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: lowItems.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = lowItems[index];
            return ListTile(
              leading: const Icon(Icons.warning, color: Colors.amber),
              title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Current Stock: ${item.quantityOnHand} ${item.unit} (Reorder level: ${item.reorderLevel})'),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

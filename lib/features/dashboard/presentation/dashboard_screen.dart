import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/database/providers.dart';
import '../../../core/utils/sync_status_chip.dart';
import '../../reports/domain/reports_service.dart';
import '../../products/domain/product_stock_info.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsService = ref.watch(reportsServiceProvider);
    final bizId = ref.watch(currentBusinessIdProvider);
    final productsAsync = ref.watch(productsStreamProvider);
    final currencyFormat = NumberFormat('#,##0', 'en_US');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tzion Stockly'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: Center(
              child: ReactiveSyncStatusChip(),
            ),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: reportsService.getDashboardKpis(bizId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final kpis = snapshot.data ?? {
            'totalStockValue': 0,
            'salesToday': 0,
            'lowStockCount': 0,
            'outOfStockCount': 0,
          };

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // KPI Cards Grid
                GridView.count(
                  crossAxisCount: MediaQuery.of(context).size.width >= 600 ? 4 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  children: [
                    _KpiCard(
                      title: 'Total Stock Value',
                      value: 'TZS ${currencyFormat.format(kpis['totalStockValue'])}',
                      icon: Icons.account_balance_wallet,
                      color: const Color(0xFF1F3864),
                      onTap: () => context.go('/reports'),
                    ),
                    _KpiCard(
                      title: 'Sales Today',
                      value: 'TZS ${currencyFormat.format(kpis['salesToday'])}',
                      icon: Icons.point_of_sale,
                      color: const Color(0xFF14B8A6),
                      onTap: () => context.go('/reports'),
                    ),
                    _KpiCard(
                      title: 'Low Stock Items',
                      value: '${kpis['lowStockCount']}',
                      icon: Icons.warning_amber,
                      color: const Color(0xFFF59E0B),
                      onTap: () => context.go('/products'),
                    ),
                    _KpiCard(
                      title: 'Out of Stock',
                      value: '${kpis['outOfStockCount']}',
                      icon: Icons.error_outline,
                      color: const Color(0xFFEF4444),
                      onTap: () => context.go('/products'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Sales Last 7 Days Line Chart
                const Text(
                  'Sales Trend (Last 7 Days)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SizedBox(
                      height: 200,
                      child: FutureBuilder<List<DailySalesData>>(
                        future: reportsService.getSalesLastNDays(bizId, days: 7),
                        builder: (context, salesSnap) {
                          if (!salesSnap.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final salesData = salesSnap.data!;
                          final spots = <FlSpot>[];
                          for (int i = 0; i < salesData.length; i++) {
                            spots.add(FlSpot(i.toDouble(), salesData[i].totalSales.toDouble()));
                          }

                          return LineChart(
                            LineChartData(
                              gridData: const FlGridData(show: false),
                              titlesData: FlTitlesData(
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      final index = value.toInt();
                                      if (index >= 0 && index < salesData.length) {
                                        return Text(
                                          DateFormat('E').format(salesData[index].date),
                                          style: const TextStyle(fontSize: 10),
                                        );
                                      }
                                      return const Text('');
                                    },
                                  ),
                                ),
                                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              borderData: FlBorderData(show: false),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: spots,
                                  isCurved: true,
                                  color: const Color(0xFF14B8A6),
                                  barWidth: 3,
                                  dotData: const FlDotData(show: true),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: const Color(0xFF14B8A6).withValues(alpha: 0.15),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Top 5 Products Bar Chart
                const Text(
                  'Top 5 Selling Products (This Month)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SizedBox(
                      height: 200,
                      child: FutureBuilder<List<TopProductSalesData>>(
                        future: reportsService.getTopProductsThisMonth(bizId, limit: 5),
                        builder: (context, topSnap) {
                          if (!topSnap.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final topProducts = topSnap.data!;
                          if (topProducts.isEmpty) {
                            return const Center(child: Text('No sales recorded this month yet.'));
                          }

                          final barGroups = <BarChartGroupData>[];
                          for (int i = 0; i < topProducts.length; i++) {
                            barGroups.add(
                              BarChartGroupData(
                                x: i,
                                barRods: [
                                  BarChartRodData(
                                    toY: topProducts[i].totalQuantitySold.toDouble(),
                                    color: const Color(0xFF1F3864),
                                    width: 16,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ],
                              ),
                            );
                          }

                          return BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              gridData: const FlGridData(show: false),
                              titlesData: FlTitlesData(
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      final index = value.toInt();
                                      if (index >= 0 && index < topProducts.length) {
                                        final name = topProducts[index].productName;
                                        final shortName = name.length > 8 ? '${name.substring(0, 8)}...' : name;
                                        return Text(shortName, style: const TextStyle(fontSize: 9));
                                      }
                                      return const Text('');
                                    },
                                  ),
                                ),
                                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              borderData: FlBorderData(show: false),
                              barGroups: barGroups,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Needs Restocking List
                const Text(
                  'Needs Restocking',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                productsAsync.when(
                  data: (products) {
                    final lowStockItems = products.where((p) => p.status != StockStatus.inStock).toList();
                    if (lowStockItems.isEmpty) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, color: Color(0xFF10B981)),
                              SizedBox(width: 12),
                              Text('All products are well stocked!'),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: lowStockItems.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = lowStockItems[index];
                        final progress = item.reorderLevel > 0 ? (item.quantityOnHand / item.reorderLevel).clamp(0.0, 1.0) : 0.0;

                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFFF59E0B),
                              child: Icon(Icons.warning, color: Colors.white),
                            ),
                            title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                LinearProgressIndicator(
                                  value: progress,
                                  backgroundColor: Colors.grey.shade200,
                                  color: item.quantityOnHand <= 0 ? Colors.red : Colors.amber,
                                ),
                                const SizedBox(height: 4),
                                Text('Stock: ${item.quantityOnHand} ${item.unit} / Reorder: ${item.reorderLevel}'),
                              ],
                            ),
                            trailing: TextButton(
                              onPressed: () => context.push('/stock'),
                              child: const Text('Restock'),
                            ),
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Error: $e'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
              const Spacer(),
              Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

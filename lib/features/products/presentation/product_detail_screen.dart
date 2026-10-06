import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/providers.dart';
import '../domain/product_stock_info.dart';

class ProductDetailScreen extends ConsumerWidget {
  final String productId;

  const ProductDetailScreen({super.key, required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dbService = ref.watch(databaseServiceProvider);
    final currencyFormat = NumberFormat('#,##0', 'en_US');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: 'Archive Product',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Archive Product?'),
                  content: const Text('This will soft-delete the product from list view, but its stock movement history will remain intact.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Archive'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await dbService.softDeleteProduct(productId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Product archived offline.')),
                  );
                  context.pop();
                }
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<ProductStockInfo?>(
        future: dbService.getProductStockInfo(productId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final info = snapshot.data;
          if (info == null) {
            return const Center(child: Text('Product not found.'));
          }

          Color statusColor;
          String statusText;
          switch (info.status) {
            case StockStatus.inStock:
              statusColor = const Color(0xFF10B981);
              statusText = 'In Stock';
              break;
            case StockStatus.lowStock:
              statusColor = const Color(0xFFF59E0B);
              statusText = 'Low Stock';
              break;
            case StockStatus.outOfStock:
              statusColor = const Color(0xFFEF4444);
              statusText = 'Out of Stock';
              break;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              info.name,
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                            if (info.categoryName != null)
                              Text(
                                info.categoryName!,
                                style: const TextStyle(fontSize: 14, color: Colors.grey),
                              ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: statusColor),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Stock & Pricing Info', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const Divider(),
                        _infoRow('Quantity On Hand:', '${info.quantityOnHand} ${info.unit}', bold: true),
                        _infoRow('Reorder Level:', '${info.reorderLevel} ${info.unit}'),
                        _infoRow('Cost Price:', 'TZS ${currencyFormat.format(info.costPrice)}'),
                        _infoRow('Selling Price:', 'TZS ${currencyFormat.format(info.sellingPrice)}'),
                        if (info.barcode != null) _infoRow('Barcode:', info.barcode!),
                        if (info.sku != null) _infoRow('SKU:', info.sku!),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                const Text('Stock Movement History (Append-Only)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),

                StreamBuilder(
                  stream: dbService.watchMovements(productId),
                  builder: (context, moveSnapshot) {
                    if (!moveSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final movements = moveSnapshot.data!;
                    if (movements.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('No stock movements recorded yet.'),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: movements.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final m = movements[index];
                        final isPositive = m.quantity > 0;
                        final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(m.occurredAt);

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isPositive
                                ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                : const Color(0xFFEF4444).withValues(alpha: 0.2),
                            child: Icon(
                              isPositive ? Icons.arrow_downward : Icons.arrow_upward,
                              color: isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            ),
                          ),
                          title: Text(
                            '${m.type.toUpperCase()} (${isPositive ? '+' : ''}${m.quantity})',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text('$dateStr ${m.note != null ? "• ${m.note}" : ""}'),
                          trailing: Text(
                            'TZS ${currencyFormat.format(m.unitPrice)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontSize: bold ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }
}

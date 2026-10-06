import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/database/providers.dart';
import '../../../core/utils/seed_data.dart';
import '../domain/product_stock_info.dart';

class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsStreamProvider);
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    final selectedCategory = ref.watch(selectedCategoryFilterProvider);
    final dbService = ref.watch(databaseServiceProvider);
    final bizId = ref.watch(currentBusinessIdProvider);
    final currencyFormat = NumberFormat('#,##0', 'en_US');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Products Catalog'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'seed') {
                final seeder = SeedDataService(dbService);
                await seeder.seedTanzanianShopData(bizId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('30 Tanzanian shop products seeded offline!')),
                  );
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'seed',
                child: Row(
                  children: [
                    Icon(Icons.grain, color: Color(0xFF14B8A6)),
                    SizedBox(width: 8),
                    Text('Seed 30 Shop Products'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Header
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search products by name, barcode, or SKU...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: (val) {
                    ref.read(searchQueryProvider.notifier).state = val;
                  },
                ),
                const SizedBox(height: 8),

                // Category Chips Horizontal List
                categoriesAsync.when(
                  data: (categories) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('All Categories'),
                            selected: selectedCategory == null,
                            onSelected: (_) {
                              ref.read(selectedCategoryFilterProvider.notifier).state = null;
                            },
                          ),
                          const SizedBox(width: 8),
                          ...categories.map((c) {
                            final isSelected = selectedCategory == c.id;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ChoiceChip(
                                label: Text(c.name),
                                selected: isSelected,
                                onSelected: (selected) {
                                  ref.read(selectedCategoryFilterProvider.notifier).state = selected ? c.id : null;
                                },
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Products List
          Expanded(
            child: productsAsync.when(
              data: (products) {
                if (products.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text('No products found', style: TextStyle(fontSize: 18, color: Colors.grey)),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1F3864),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            final seeder = SeedDataService(dbService);
                            await seeder.seedTanzanianShopData(bizId);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('30 Tanzanian shop products seeded offline!')),
                              );
                            }
                          },
                          icon: const Icon(Icons.grain),
                          label: const Text('Seed 30 Tanzanian Shop Products'),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: products.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = products[index];

                    Color badgeColor;
                    String badgeLabel;
                    switch (item.status) {
                      case StockStatus.inStock:
                        badgeColor = const Color(0xFF10B981);
                        badgeLabel = 'In Stock (${item.quantityOnHand})';
                        break;
                      case StockStatus.lowStock:
                        badgeColor = const Color(0xFFF59E0B);
                        badgeLabel = 'Low Stock (${item.quantityOnHand})';
                        break;
                      case StockStatus.outOfStock:
                        badgeColor = const Color(0xFFEF4444);
                        badgeLabel = 'Out of Stock (0)';
                        break;
                    }

                    return Card(
                      child: ListTile(
                        onTap: () {
                          context.push('/product/${item.id}');
                        },
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF1F3864).withValues(alpha: 0.1),
                          child: const Icon(Icons.shopping_bag, color: Color(0xFF1F3864)),
                        ),
                        title: Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${item.categoryName ?? "General"} • TZS ${currencyFormat.format(item.sellingPrice)} per ${item.unit}',
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: badgeColor),
                          ),
                          child: Text(
                            badgeLabel,
                            style: TextStyle(
                              color: badgeColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1F3864),
        foregroundColor: Colors.white,
        onPressed: () {
          context.push('/add-product');
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
      ),
    );
  }
}

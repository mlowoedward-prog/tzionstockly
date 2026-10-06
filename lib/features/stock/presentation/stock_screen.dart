import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/providers.dart';
import '../../products/domain/product_stock_info.dart';
import '../domain/stock_service.dart';

class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});

  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  final _formKey = GlobalKey<FormState>();
  String _movementType = 'sale'; // 'purchase', 'sale', 'adjustment', 'return', 'damage'
  ProductStockInfo? _selectedProduct;
  final _quantityController = TextEditingController(text: '1');
  final _unitCostController = TextEditingController(text: '0');
  final _unitPriceController = TextEditingController(text: '0');
  final _noteController = TextEditingController();
  String? _selectedPartnerId;
  bool _isSaving = false;

  @override
  void dispose() {
    _quantityController.dispose();
    _unitCostController.dispose();
    _unitPriceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onProductSelected(ProductStockInfo? p) {
    setState(() {
      _selectedProduct = p;
      if (p != null) {
        _unitCostController.text = p.costPrice.toString();
        _unitPriceController.text = p.sellingPrice.toString();
      }
    });
  }

  Future<void> _recordStockEntry() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a product first.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final stockService = ref.read(stockServiceProvider);
      final bizId = ref.read(currentBusinessIdProvider);
      final qty = int.tryParse(_quantityController.text.trim()) ?? 1;
      final cost = int.tryParse(_unitCostController.text.trim()) ?? _selectedProduct!.costPrice;
      final price = int.tryParse(_unitPriceController.text.trim()) ?? _selectedProduct!.sellingPrice;
      final note = _noteController.text.trim().isEmpty ? null : _noteController.text.trim();

      StockServiceResult result;

      switch (_movementType) {
        case 'purchase':
          result = await stockService.recordPurchase(
            businessId: bizId,
            productId: _selectedProduct!.id,
            quantity: qty,
            unitCost: cost,
            unitPrice: price,
            partnerId: _selectedPartnerId,
            note: note,
          );
          break;
        case 'sale':
          result = await stockService.recordSale(
            businessId: bizId,
            productId: _selectedProduct!.id,
            quantity: qty,
            unitCost: cost,
            unitPrice: price,
            partnerId: _selectedPartnerId,
            note: note,
          );
          break;
        case 'adjustment':
          result = await stockService.recordAdjustment(
            businessId: bizId,
            productId: _selectedProduct!.id,
            signedQuantity: qty,
            unitCost: cost,
            unitPrice: price,
            note: note,
          );
          break;
        case 'damage':
          result = await stockService.recordDamage(
            businessId: bizId,
            productId: _selectedProduct!.id,
            quantity: qty,
            unitCost: cost,
            unitPrice: price,
            note: note,
          );
          break;
        case 'return':
          result = await stockService.recordReturn(
            businessId: bizId,
            productId: _selectedProduct!.id,
            quantity: qty,
            unitCost: cost,
            unitPrice: price,
            partnerId: _selectedPartnerId,
            note: note,
          );
          break;
        default:
          result = StockServiceResult(success: false, errorMessage: 'Invalid movement type');
      }

      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.offline_pin, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(result.warningMessage ?? 'Stock movement recorded offline!'),
                ],
              ),
              backgroundColor: result.warningMessage != null ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
            ),
          );
          // Reset form
          _quantityController.text = '1';
          _noteController.clear();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.errorMessage ?? 'Failed to record stock movement.'),
              backgroundColor: const Color(0xFFEF4444),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsStreamProvider);
    final partnersAsync = ref.watch(partnersStreamProvider(
      _movementType == 'purchase' ? 'supplier' : (_movementType == 'sale' ? 'customer' : null),
    ));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Movement Entry'),
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Select Operation Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),

                    // Movement Type Segmented Control
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'sale', label: Text('Sale'), icon: Icon(Icons.point_of_sale)),
                          ButtonSegment(value: 'purchase', label: Text('Stock In (Purchase)'), icon: Icon(Icons.add_shopping_cart)),
                          ButtonSegment(value: 'adjustment', label: Text('Adjustment'), icon: Icon(Icons.tune)),
                          ButtonSegment(value: 'damage', label: Text('Damage/Loss'), icon: Icon(Icons.remove_circle_outline)),
                          ButtonSegment(value: 'return', label: Text('Return'), icon: Icon(Icons.assignment_return)),
                        ],
                        selected: {_movementType},
                        onSelectionChanged: (set) {
                          setState(() {
                            _movementType = set.first;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Product Selector
                    productsAsync.when(
                      data: (products) {
                        return DropdownButtonFormField<ProductStockInfo>(
                          initialValue: _selectedProduct,
                          decoration: const InputDecoration(
                            labelText: 'Select Product *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.shopping_bag_outlined),
                          ),
                          items: products.map((p) {
                            return DropdownMenuItem(
                              value: p,
                              child: Text('${p.name} (Stock: ${p.quantityOnHand} ${p.unit})'),
                            );
                          }).toList(),
                          onChanged: _onProductSelected,
                        );
                      },
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('Error loading products: $e'),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _quantityController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: _movementType == 'adjustment' ? 'Signed Quantity (+ / -)' : 'Quantity',
                              border: const OutlineInputBorder(),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return 'Enter quantity';
                              final parsed = int.tryParse(val.trim());
                              if (parsed == null) return 'Invalid number';
                              if (_movementType != 'adjustment' && parsed <= 0) {
                                return 'Quantity must be > 0';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _unitPriceController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Unit Price (TZS)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    partnersAsync.when(
                      data: (partners) {
                        if (partners.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedPartnerId,
                            decoration: InputDecoration(
                              labelText: _movementType == 'purchase' ? 'Supplier (Optional)' : 'Customer (Optional)',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.person_outline),
                            ),
                            items: partners.map((part) {
                              return DropdownMenuItem(
                                value: part.id,
                                child: Text(part.name),
                              );
                            }).toList(),
                            onChanged: (val) => setState(() => _selectedPartnerId = val),
                          ),
                        );
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),

                    TextFormField(
                      controller: _noteController,
                      decoration: const InputDecoration(
                        labelText: 'Note / Reason (Optional)',
                        hintText: 'e.g. Receipt #1042, Damaged during transport',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1F3864),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _recordStockEntry,
                        icon: const Icon(Icons.check_circle),
                        label: Text('Record ${_movementType.toUpperCase()} Movement Offline', style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

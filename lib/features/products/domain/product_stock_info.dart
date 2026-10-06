enum StockStatus { inStock, lowStock, outOfStock }

class ProductStockInfo {
  final String id;
  final String businessId;
  final String name;
  final String? sku;
  final String? barcode;
  final String unit;
  final int costPrice;
  final int sellingPrice;
  final int reorderLevel;
  final String? categoryId;
  final String? categoryName;
  final String? imagePath;
  final int quantityOnHand;
  final StockStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  ProductStockInfo({
    required this.id,
    required this.businessId,
    required this.name,
    this.sku,
    this.barcode,
    required this.unit,
    required this.costPrice,
    required this.sellingPrice,
    required this.reorderLevel,
    this.categoryId,
    this.categoryName,
    this.imagePath,
    required this.quantityOnHand,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  static StockStatus calculateStatus(int quantity, int reorderLevel) {
    if (quantity <= 0) {
      return StockStatus.outOfStock;
    } else if (quantity <= reorderLevel) {
      return StockStatus.lowStock;
    } else {
      return StockStatus.inStock;
    }
  }
}

import '../../../core/database/database_service.dart';
import '../../../core/database/app_database.dart';

enum NegativeStockPolicy { allowWithWarning, block }

class StockServiceResult {
  final bool success;
  final String? warningMessage;
  final String? errorMessage;
  final StockMovement? movement;

  StockServiceResult({
    required this.success,
    this.warningMessage,
    this.errorMessage,
    this.movement,
  });
}

class StockService {
  final DatabaseService dbService;
  NegativeStockPolicy negativeStockPolicy;

  StockService({
    required this.dbService,
    this.negativeStockPolicy = NegativeStockPolicy.allowWithWarning,
  });

  /// Record a Purchase movement (+ quantity)
  Future<StockServiceResult> recordPurchase({
    required String businessId,
    required String productId,
    required int quantity,
    required int unitCost,
    required int unitPrice,
    String? partnerId,
    String? note,
    DateTime? occurredAt,
  }) async {
    if (quantity <= 0) {
      return StockServiceResult(success: false, errorMessage: 'Purchase quantity must be greater than zero.');
    }
    final movement = await dbService.recordStockMovement(
      businessId: businessId,
      productId: productId,
      type: 'purchase',
      signedQuantity: quantity,
      unitCost: unitCost,
      unitPrice: unitPrice,
      partnerId: partnerId,
      note: note,
      occurredAt: occurredAt,
    );
    return StockServiceResult(success: true, movement: movement);
  }

  /// Record a Sale movement (- quantity)
  Future<StockServiceResult> recordSale({
    required String businessId,
    required String productId,
    required int quantity,
    required int unitCost,
    required int unitPrice,
    String? partnerId,
    String? note,
    DateTime? occurredAt,
  }) async {
    if (quantity <= 0) {
      return StockServiceResult(success: false, errorMessage: 'Sale quantity must be greater than zero.');
    }

    final currentStock = await dbService.getQuantityOnHand(productId);
    final resultingStock = currentStock - quantity;

    String? warning;
    if (resultingStock < 0) {
      if (negativeStockPolicy == NegativeStockPolicy.block) {
        return StockServiceResult(
          success: false,
          errorMessage: 'Sale blocked: Stock cannot be negative ($currentStock available, requested $quantity).',
        );
      } else {
        warning = 'Warning: Stock is now negative ($resultingStock $unitCost).';
      }
    }

    final movement = await dbService.recordStockMovement(
      businessId: businessId,
      productId: productId,
      type: 'sale',
      signedQuantity: -quantity, // negative signed quantity
      unitCost: unitCost,
      unitPrice: unitPrice,
      partnerId: partnerId,
      note: note,
      occurredAt: occurredAt,
    );

    return StockServiceResult(
      success: true,
      warningMessage: warning,
      movement: movement,
    );
  }

  /// Record an Adjustment movement (+ or - quantity)
  Future<StockServiceResult> recordAdjustment({
    required String businessId,
    required String productId,
    required int signedQuantity,
    required int unitCost,
    required int unitPrice,
    String? note,
    DateTime? occurredAt,
  }) async {
    if (signedQuantity == 0) {
      return StockServiceResult(success: false, errorMessage: 'Adjustment quantity cannot be zero.');
    }

    final movement = await dbService.recordStockMovement(
      businessId: businessId,
      productId: productId,
      type: 'adjustment',
      signedQuantity: signedQuantity,
      unitCost: unitCost,
      unitPrice: unitPrice,
      note: note,
      occurredAt: occurredAt,
    );

    return StockServiceResult(success: true, movement: movement);
  }

  /// Record Damage / Loss movement (- quantity)
  Future<StockServiceResult> recordDamage({
    required String businessId,
    required String productId,
    required int quantity,
    required int unitCost,
    required int unitPrice,
    String? note,
    DateTime? occurredAt,
  }) async {
    if (quantity <= 0) {
      return StockServiceResult(success: false, errorMessage: 'Damage quantity must be greater than zero.');
    }

    final movement = await dbService.recordStockMovement(
      businessId: businessId,
      productId: productId,
      type: 'damage',
      signedQuantity: -quantity,
      unitCost: unitCost,
      unitPrice: unitPrice,
      note: note,
      occurredAt: occurredAt,
    );

    return StockServiceResult(success: true, movement: movement);
  }

  /// Record Return movement (+ quantity)
  Future<StockServiceResult> recordReturn({
    required String businessId,
    required String productId,
    required int quantity,
    required int unitCost,
    required int unitPrice,
    String? partnerId,
    String? note,
    DateTime? occurredAt,
  }) async {
    if (quantity <= 0) {
      return StockServiceResult(success: false, errorMessage: 'Return quantity must be greater than zero.');
    }

    final movement = await dbService.recordStockMovement(
      businessId: businessId,
      productId: productId,
      type: 'return',
      signedQuantity: quantity,
      unitCost: unitCost,
      unitPrice: unitPrice,
      partnerId: partnerId,
      note: note,
      occurredAt: occurredAt,
    );

    return StockServiceResult(success: true, movement: movement);
  }
}

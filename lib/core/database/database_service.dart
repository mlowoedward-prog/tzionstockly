import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'app_database.dart';
import '../../features/products/domain/product_stock_info.dart';

class DatabaseService {
  final AppDatabase db;
  final _uuid = const Uuid();

  DatabaseService(this.db);

  static const String defaultBusinessId = '00000000-0000-0000-0000-000000000001';

  /// Ensures default business exists on first launch
  Future<String> ensureDefaultBusiness() async {
    final existing = await (db.select(db.businesses)..where((b) => b.id.equals(defaultBusinessId))).getSingleOrNull();
    if (existing != null) {
      return existing.id;
    }
    final now = DateTime.now();
    await db.into(db.businesses).insert(
          BusinessesCompanion.insert(
            id: defaultBusinessId,
            name: 'Default Shop',
            currency: const Value('TZS'),
            createdAt: now,
            updatedAt: now,
            synced: const Value(false),
          ),
        );
    return defaultBusinessId;
  }

  // ==================== CATEGORIES ====================

  Stream<List<Category>> watchCategories(String businessId) {
    return (db.select(db.categories)
          ..where((c) => c.businessId.equals(businessId) & c.deletedAt.isNull())
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .watch();
  }

  Future<List<Category>> getCategories(String businessId) {
    return (db.select(db.categories)
          ..where((c) => c.businessId.equals(businessId) & c.deletedAt.isNull())
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .get();
  }

  Future<Category> createCategory({
    required String businessId,
    required String name,
  }) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    final companion = CategoriesCompanion.insert(
      id: id,
      businessId: businessId,
      name: name,
      createdAt: now,
      updatedAt: now,
      synced: const Value(false),
    );

    return db.transaction(() async {
      await db.into(db.categories).insert(companion);
      await _addToSyncQueue('categories', id, 'insert', {
        'id': id,
        'business_id': businessId,
        'name': name,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      return (await (db.select(db.categories)..where((c) => c.id.equals(id))).getSingle());
    });
  }

  // ==================== PARTNERS ====================

  Stream<List<Partner>> watchPartners(String businessId, {String? type}) {
    final query = db.select(db.partners)
      ..where((p) => p.businessId.equals(businessId) & p.deletedAt.isNull());
    if (type != null) {
      query.where((p) => p.type.equals(type));
    }
    query.orderBy([(p) => OrderingTerm.asc(p.name)]);
    return query.watch();
  }

  Future<Partner> createPartner({
    required String businessId,
    required String name,
    required String type, // 'supplier' or 'customer'
    String? phone,
    String? email,
  }) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    final companion = PartnersCompanion.insert(
      id: id,
      businessId: businessId,
      name: name,
      type: type,
      phone: Value(phone),
      email: Value(email),
      createdAt: now,
      updatedAt: now,
      synced: const Value(false),
    );

    return db.transaction(() async {
      await db.into(db.partners).insert(companion);
      await _addToSyncQueue('partners', id, 'insert', {
        'id': id,
        'business_id': businessId,
        'name': name,
        'type': type,
        'phone': phone,
        'email': email,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      return (await (db.select(db.partners)..where((p) => p.id.equals(id))).getSingle());
    });
  }

  // ==================== PRODUCTS & STOCK LEDGER ====================

  Stream<List<ProductStockInfo>> watchProductsWithStock(String businessId, {String? search, String? categoryId}) {
    // Custom join/stream query for products with calculated quantity on hand
    final query = db.select(db.products)
      ..where((p) => p.businessId.equals(businessId) & p.deletedAt.isNull());

    if (categoryId != null && categoryId.isNotEmpty) {
      query.where((p) => p.categoryId.equals(categoryId));
    }

    if (search != null && search.trim().isNotEmpty) {
      final pattern = '%${search.trim().toLowerCase()}%';
      query.where((p) => p.name.lower().like(pattern) | p.barcode.lower().like(pattern) | p.sku.lower().like(pattern));
    }

    return query.watch().asyncMap((productsList) async {
      final categoriesList = await getCategories(businessId);
      final categoryMap = {for (var c in categoriesList) c.id: c.name};

      final result = <ProductStockInfo>[];
      for (final p in productsList) {
        final qty = await getQuantityOnHand(p.id);
        result.add(
          ProductStockInfo(
            id: p.id,
            businessId: p.businessId,
            name: p.name,
            sku: p.sku,
            barcode: p.barcode,
            unit: p.unit,
            costPrice: p.costPrice,
            sellingPrice: p.sellingPrice,
            reorderLevel: p.reorderLevel,
            categoryId: p.categoryId,
            categoryName: p.categoryId != null ? categoryMap[p.categoryId] : null,
            imagePath: p.imagePath,
            quantityOnHand: qty,
            status: ProductStockInfo.calculateStatus(qty, p.reorderLevel),
            createdAt: p.createdAt,
            updatedAt: p.updatedAt,
            deletedAt: p.deletedAt,
          ),
        );
      }
      return result;
    });
  }

  Future<ProductStockInfo?> getProductStockInfo(String productId) async {
    final p = await (db.select(db.products)..where((prod) => prod.id.equals(productId))).getSingleOrNull();
    if (p == null) return null;

    String? categoryName;
    if (p.categoryId != null) {
      final cat = await (db.select(db.categories)..where((c) => c.id.equals(p.categoryId!))).getSingleOrNull();
      categoryName = cat?.name;
    }

    final qty = await getQuantityOnHand(productId);
    return ProductStockInfo(
      id: p.id,
      businessId: p.businessId,
      name: p.name,
      sku: p.sku,
      barcode: p.barcode,
      unit: p.unit,
      costPrice: p.costPrice,
      sellingPrice: p.sellingPrice,
      reorderLevel: p.reorderLevel,
      categoryId: p.categoryId,
      categoryName: categoryName,
      imagePath: p.imagePath,
      quantityOnHand: qty,
      status: ProductStockInfo.calculateStatus(qty, p.reorderLevel),
      createdAt: p.createdAt,
      updatedAt: p.updatedAt,
      deletedAt: p.deletedAt,
    );
  }

  /// Calculates quantity on hand as SUM(signed quantity) of all non-deleted movements
  Future<int> getQuantityOnHand(String productId) async {
    final query = db.selectOnly(db.stockMovements)
      ..addColumns([db.stockMovements.quantity.sum()])
      ..where(db.stockMovements.productId.equals(productId) & db.stockMovements.deletedAt.isNull());
    final row = await query.getSingle();
    final sum = row.read(db.stockMovements.quantity.sum());
    return sum ?? 0;
  }

  Future<Product> createProduct({
    required String businessId,
    required String name,
    String? sku,
    String? barcode,
    required String unit,
    required int costPrice,
    required int sellingPrice,
    required int reorderLevel,
    String? categoryId,
    String? imagePath,
    int openingQuantity = 0,
  }) async {
    final now = DateTime.now();
    final productId = _uuid.v4();

    final productCompanion = ProductsCompanion.insert(
      id: productId,
      businessId: businessId,
      name: name,
      sku: Value(sku),
      barcode: Value(barcode),
      unit: Value(unit),
      costPrice: Value(costPrice),
      sellingPrice: Value(sellingPrice),
      reorderLevel: Value(reorderLevel),
      categoryId: Value(categoryId),
      imagePath: Value(imagePath),
      createdAt: now,
      updatedAt: now,
      synced: const Value(false),
    );

    return db.transaction(() async {
      await db.into(db.products).insert(productCompanion);

      await _addToSyncQueue('products', productId, 'insert', {
        'id': productId,
        'business_id': businessId,
        'name': name,
        'sku': sku,
        'barcode': barcode,
        'unit': unit,
        'cost_price': costPrice,
        'selling_price': sellingPrice,
        'reorder_level': reorderLevel,
        'category_id': categoryId,
        'image_path': imagePath,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      // If opening quantity > 0, record an initial purchase stock movement
      if (openingQuantity > 0) {
        await _recordMovementInTransaction(
          businessId: businessId,
          productId: productId,
          type: 'purchase',
          quantity: openingQuantity,
          unitCost: costPrice,
          unitPrice: sellingPrice,
          note: 'Opening Stock',
          occurredAt: now,
        );
      }

      return (await (db.select(db.products)..where((p) => p.id.equals(productId))).getSingle());
    });
  }

  Future<void> softDeleteProduct(String productId) async {
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(db.products)..where((p) => p.id.equals(productId))).write(
        ProductsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          synced: const Value(false),
        ),
      );
      await _addToSyncQueue('products', productId, 'delete', {
        'id': productId,
        'deleted_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
    });
  }

  // ==================== APPEND-ONLY STOCK MOVEMENTS ====================

  Stream<List<StockMovement>> watchMovements(String productId) {
    return (db.select(db.stockMovements)
          ..where((m) => m.productId.equals(productId) & m.deletedAt.isNull())
          ..orderBy([(m) => OrderingTerm.desc(m.occurredAt)]))
        .watch();
  }

  Future<StockMovement> recordStockMovement({
    required String businessId,
    required String productId,
    required String type, // 'purchase', 'sale', 'adjustment', 'return', 'damage'
    required int signedQuantity,
    required int unitCost,
    required int unitPrice,
    String? partnerId,
    String? note,
    DateTime? occurredAt,
  }) async {
    return db.transaction(() async {
      return _recordMovementInTransaction(
        businessId: businessId,
        productId: productId,
        type: type,
        quantity: signedQuantity,
        unitCost: unitCost,
        unitPrice: unitPrice,
        partnerId: partnerId,
        note: note,
        occurredAt: occurredAt ?? DateTime.now(),
      );
    });
  }

  Future<StockMovement> _recordMovementInTransaction({
    required String businessId,
    required String productId,
    required String type,
    required int quantity,
    required int unitCost,
    required int unitPrice,
    String? partnerId,
    String? note,
    required DateTime occurredAt,
  }) async {
    final now = DateTime.now();
    final id = _uuid.v4();

    final companion = StockMovementsCompanion.insert(
      id: id,
      businessId: businessId,
      productId: productId,
      type: type,
      quantity: quantity,
      unitCost: Value(unitCost),
      unitPrice: Value(unitPrice),
      partnerId: Value(partnerId),
      note: Value(note),
      occurredAt: occurredAt,
      createdAt: now,
      updatedAt: now,
      synced: const Value(false),
    );

    await db.into(db.stockMovements).insert(companion);

    await _addToSyncQueue('stock_movements', id, 'insert', {
      'id': id,
      'business_id': businessId,
      'product_id': productId,
      'type': type,
      'quantity': quantity,
      'unit_cost': unitCost,
      'unit_price': unitPrice,
      'partner_id': partnerId,
      'note': note,
      'occurred_at': occurredAt.toIso8601String(),
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    return (await (db.select(db.stockMovements)..where((m) => m.id.equals(id))).getSingle());
  }

  // Helper: insert sync queue row inside transaction
  Future<void> _addToSyncQueue(
    String targetTable,
    String recordId,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    await db.into(db.syncQueue).insert(
          SyncQueueCompanion.insert(
            targetTable: targetTable,
            recordId: recordId,
            operation: operation,
            payload: jsonEncode(payload),
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<int> getSyncQueueCount() async {
    final query = db.selectOnly(db.syncQueue)..addColumns([db.syncQueue.id.count()]);
    final row = await query.getSingle();
    return row.read(db.syncQueue.id.count()) ?? 0;
  }

  /// Transactionally re-assigns all offline local data created under `defaultBusinessId`
  /// to [targetBusinessId] so that it pushes to the newly authenticated cloud business account.
  Future<void> adoptDefaultBusinessData(String targetBusinessId) async {
    if (targetBusinessId == defaultBusinessId) return;

    await db.transaction(() async {
      final now = DateTime.now();

      // 1. Categories
      await (db.update(db.categories)..where((c) => c.businessId.equals(defaultBusinessId))).write(
        CategoriesCompanion(businessId: Value(targetBusinessId), synced: const Value(false), updatedAt: Value(now)),
      );

      // 2. Partners
      await (db.update(db.partners)..where((p) => p.businessId.equals(defaultBusinessId))).write(
        PartnersCompanion(businessId: Value(targetBusinessId), synced: const Value(false), updatedAt: Value(now)),
      );

      // 3. Products
      await (db.update(db.products)..where((p) => p.businessId.equals(defaultBusinessId))).write(
        ProductsCompanion(businessId: Value(targetBusinessId), synced: const Value(false), updatedAt: Value(now)),
      );

      // 4. Stock Movements
      await (db.update(db.stockMovements)..where((m) => m.businessId.equals(defaultBusinessId))).write(
        StockMovementsCompanion(businessId: Value(targetBusinessId), synced: const Value(false), updatedAt: Value(now)),
      );
    });
  }
}


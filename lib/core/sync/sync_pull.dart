import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/database_service.dart';
import '../database/app_database.dart';

class SyncPullEngine {
  final DatabaseService dbService;
  final SupabaseClient? supabaseClient;

  SyncPullEngine({required this.dbService, required this.supabaseClient});

  AppDatabase get db => dbService.db;

  /// Executes pull sync for all synced tables
  Future<void> pullRemoteChanges(String businessId) async {
    if (supabaseClient == null) return;

    final tables = ['categories', 'partners', 'products', 'stock_movements'];

    for (final table in tables) {
      await _pullTable(table, businessId);
    }
  }

  Future<void> _pullTable(String table, String businessId) async {
    // 1. Get last_pulled_at for this table
    final syncState = await (db.select(db.syncState)..where((s) => s.targetTable.equals(table))).getSingleOrNull();
    final lastPulled = syncState?.lastPulledAt;

    // 2. Fetch remote records updated after last_pulled_at
    var query = supabaseClient!.from(table).select().eq('business_id', businessId);
    if (lastPulled != null) {
      query = query.gt('updated_at', lastPulled.toIso8601String());
    }

    final List<dynamic> remoteRows = await query;
    if (remoteRows.isEmpty) return;

    final nowPullTime = DateTime.now();

    // 3. Apply remote changes inside single transaction
    await db.transaction(() async {
      for (final row in remoteRows) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(row as Map);
        final String recordId = data['id'] as String;

        // Check if there is a pending local change in sync_queue for this record
        final pendingLocal = await (db.select(db.syncQueue)
              ..where((q) => q.targetTable.equals(table) & q.recordId.equals(recordId)))
            .getSingleOrNull();

        // Skip remote row if local change is pending and newer
        if (pendingLocal != null) {
          continue;
        }

        // Apply to local table
        await _applyRemoteRowToLocalTable(table, data);
      }

      // 4. Save last_pulled_at only after transaction commits successfully
      await db.into(db.syncState).insertOnConflictUpdate(
            SyncStateCompanion.insert(
              targetTable: table,
              lastPulledAt: Value(nowPullTime),
            ),
          );
    });
  }

  Future<void> _applyRemoteRowToLocalTable(String table, Map<String, dynamic> data) async {
    final String id = data['id'];
    final String businessId = data['business_id'];
    final DateTime createdAt = DateTime.parse(data['created_at']);
    final DateTime updatedAt = DateTime.parse(data['updated_at']);
    final DateTime? deletedAt = data['deleted_at'] != null ? DateTime.parse(data['deleted_at']) : null;

    switch (table) {
      case 'categories':
        await db.into(db.categories).insertOnConflictUpdate(
              CategoriesCompanion.insert(
                id: id,
                businessId: businessId,
                name: data['name'],
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: Value(deletedAt),
                synced: const Value(true),
              ),
            );
        break;
      case 'partners':
        await db.into(db.partners).insertOnConflictUpdate(
              PartnersCompanion.insert(
                id: id,
                businessId: businessId,
                name: data['name'],
                type: data['type'],
                phone: Value(data['phone']),
                email: Value(data['email']),
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: Value(deletedAt),
                synced: const Value(true),
              ),
            );
        break;
      case 'products':
        await db.into(db.products).insertOnConflictUpdate(
              ProductsCompanion.insert(
                id: id,
                businessId: businessId,
                name: data['name'],
                sku: Value(data['sku']),
                barcode: Value(data['barcode']),
                unit: Value(data['unit'] ?? 'pcs'),
                costPrice: Value(data['cost_price'] ?? 0),
                sellingPrice: Value(data['selling_price'] ?? 0),
                reorderLevel: Value(data['reorder_level'] ?? 5),
                categoryId: Value(data['category_id']),
                imagePath: Value(data['image_path']),
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: Value(deletedAt),
                synced: const Value(true),
              ),
            );
        break;
      case 'stock_movements':
        await db.into(db.stockMovements).insertOnConflictUpdate(
              StockMovementsCompanion.insert(
                id: id,
                businessId: businessId,
                productId: data['product_id'],
                type: data['type'],
                quantity: data['quantity'],
                unitCost: Value(data['unit_cost'] ?? 0),
                unitPrice: Value(data['unit_price'] ?? 0),
                partnerId: Value(data['partner_id']),
                note: Value(data['note']),
                createdBy: Value(data['created_by'] ?? 'remote'),
                occurredAt: DateTime.parse(data['occurred_at']),
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: Value(deletedAt),
                synced: const Value(true),
              ),
            );
        break;
    }
  }
}

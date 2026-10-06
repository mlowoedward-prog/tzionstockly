import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/database_service.dart';
import '../database/app_database.dart';

class SyncPushEngine {
  final DatabaseService dbService;
  final SupabaseClient? supabaseClient;

  SyncPushEngine({required this.dbService, required this.supabaseClient});

  AppDatabase get db => dbService.db;

  /// Executes push sync: processes pending sync_queue items in FIFO order
  Future<int> pushPendingChanges() async {
    if (supabaseClient == null) return 0;

    final queueItems = await (db.select(db.syncQueue)
          ..orderBy([(q) => OrderingTerm.asc(q.createdAt)]))
        .get();

    if (queueItems.isEmpty) return 0;

    int pushedCount = 0;

    for (final item in queueItems) {
      try {
        final payload = jsonDecode(item.payload) as Map<String, dynamic>;

        // Send idempotent upsert to Supabase
        await supabaseClient!.from(item.targetTable).upsert(payload);

        // On success: remove queue item and mark local record as synced
        await db.transaction(() async {
          await (db.delete(db.syncQueue)..where((q) => q.id.equals(item.id))).go();
          await _markLocalRecordSynced(item.targetTable, item.recordId);
        });

        pushedCount++;
      } catch (e) {
        // On failure: increment attempts, store error message
        final errorMsg = e.toString();
        await (db.update(db.syncQueue)..where((q) => q.id.equals(item.id))).write(
          SyncQueueCompanion(
            attempts: Value(item.attempts + 1),
            lastError: Value(errorMsg),
          ),
        );
        // Break push loop on error to preserve FIFO ordering
        rethrow;
      }
    }

    return pushedCount;
  }

  Future<void> _markLocalRecordSynced(String table, String recordId) async {
    switch (table) {
      case 'categories':
        await (db.update(db.categories)..where((c) => c.id.equals(recordId))).write(
          const CategoriesCompanion(synced: Value(true)),
        );
        break;
      case 'products':
        await (db.update(db.products)..where((p) => p.id.equals(recordId))).write(
          const ProductsCompanion(synced: Value(true)),
        );
        break;
      case 'partners':
        await (db.update(db.partners)..where((p) => p.id.equals(recordId))).write(
          const PartnersCompanion(synced: Value(true)),
        );
        break;
      case 'stock_movements':
        await (db.update(db.stockMovements)..where((m) => m.id.equals(recordId))).write(
          const StockMovementsCompanion(synced: Value(true)),
        );
        break;
      case 'businesses':
        await (db.update(db.businesses)..where((b) => b.id.equals(recordId))).write(
          const BusinessesCompanion(synced: Value(true)),
        );
        break;
    }
  }
}

import 'package:drift/drift.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Businesses,
  Categories,
  Products,
  Partners,
  StockMovements,
  SyncQueue,
  SyncState,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(QueryExecutor e) : super(e);

  AppDatabase.forTesting(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Add required indexes per AGENT_RULES.md
          await customStatement('CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode);');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_stock_movements_prod_time ON stock_movements(product_id, occurred_at);');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_products_biz_updated ON products(business_id, updated_at);');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_stock_movements_biz_updated ON stock_movements(business_id, updated_at);');
        },
        onUpgrade: (m, from, to) async {
          // Schema v1 setup
        },
      );
}

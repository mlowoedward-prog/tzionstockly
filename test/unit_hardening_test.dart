import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:tzion_stockly/core/database/app_database.dart';
import 'package:tzion_stockly/core/database/database_service.dart';
import 'package:tzion_stockly/core/utils/import_service.dart';
import 'package:tzion_stockly/core/utils/diagnostics_logger.dart';

void main() {
  late AppDatabase db;
  late DatabaseService dbService;
  late ImportService importService;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dbService = DatabaseService(db);
    importService = ImportService(dbService);
    await dbService.ensureDefaultBusiness();
  });

  tearDown(() async {
    await db.close();
  });

  group('Prompt 5 Hardening & Data Import Unit Tests', () {
    test('DiagnosticsLogger sanitizes tokens and logs events', () {
      DiagnosticsLogger.clear();
      DiagnosticsLogger.log('sync', 'Auth session eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.token_payload.signature valid');
      
      final logs = DiagnosticsLogger.getLogs();
      expect(logs.length, equals(1));
      expect(logs.first.message, contains('[TOKEN_REDACTED]'));
      expect(logs.first.category, equals('sync'));
    });

    test('ImportService validates CSV rows and transactionally imports products', () async {
      const csvData = '''name,unit,cost_price,selling_price,reorder_level,opening_quantity
Mchele wa Kyela 1kg,Kg,2000,2600,10,25
Unga wa Sembe 2kg,Begi,3000,3800,15,40
''';
      final tempFile = File('${Directory.systemTemp.path}/test_import.csv');
      await tempFile.writeAsString(csvData);

      final preview = await importService.parseAndValidateCsv(tempFile);
      expect(preview.length, equals(2));
      expect(preview.first.name, equals('Mchele wa Kyela 1kg'));
      expect(preview.first.isValid, isTrue);

      final count = await importService.executeImport(
        businessId: DatabaseService.defaultBusinessId,
        items: preview,
      );
      expect(count, equals(2));

      final prods = await dbService.watchProductsWithStock(DatabaseService.defaultBusinessId).first;
      expect(prods.length, equals(2));

      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    });
  });
}

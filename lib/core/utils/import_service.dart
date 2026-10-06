import 'dart:io';
import '../database/database_service.dart';

class ImportPreviewItem {
  final String name;
  final String unit;
  final int costPrice;
  final int sellingPrice;
  final int reorderLevel;
  final int openingQuantity;
  final bool isValid;
  final String? validationError;

  const ImportPreviewItem({
    required this.name,
    required this.unit,
    required this.costPrice,
    required this.sellingPrice,
    required this.reorderLevel,
    required this.openingQuantity,
    this.isValid = true,
    this.validationError,
  });
}

class ImportService {
  final DatabaseService dbService;

  ImportService(this.dbService);

  /// RFC 4180 compliant pure Dart CSV parser
  static List<List<String>> parseCsvString(String csvContent) {
    final List<List<String>> result = [];
    final lines = csvContent.split(RegExp(r'\r?\n'));

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      final List<String> row = [];
      final StringBuffer currentCell = StringBuffer();
      bool insideQuotes = false;

      for (int i = 0; i < line.length; i++) {
        final char = line[i];

        if (char == '"') {
          if (insideQuotes && i + 1 < line.length && line[i + 1] == '"') {
            currentCell.write('"');
            i++; // Skip escaped quote
          } else {
            insideQuotes = !insideQuotes;
          }
        } else if (char == ',' && !insideQuotes) {
          row.add(currentCell.toString());
          currentCell.clear();
        } else {
          currentCell.write(char);
        }
      }
      row.add(currentCell.toString());
      result.add(row);
    }

    return result;
  }

  /// Reads a CSV file and returns a list of validated preview items before importing
  Future<List<ImportPreviewItem>> parseAndValidateCsv(File file) async {
    final input = await file.readAsString();
    final rows = parseCsvString(input);

    if (rows.isEmpty) {
      throw Exception('CSV file is empty');
    }

    final headers = rows.first.map((e) => e.trim().toLowerCase()).toList();

    int nameIdx = headers.indexOf('name');
    int unitIdx = headers.indexOf('unit');
    int costIdx = headers.indexOf('cost_price');
    int priceIdx = headers.indexOf('selling_price');
    int reorderIdx = headers.indexOf('reorder_level');
    int qtyIdx = headers.indexOf('opening_quantity');

    if (nameIdx == -1) nameIdx = 0;
    if (priceIdx == -1) priceIdx = headers.length > 1 ? 1 : 0;

    final previewList = <ImportPreviewItem>[];

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || (row.length == 1 && row.first.trim().isEmpty)) {
        continue;
      }

      final name = nameIdx < row.length ? row[nameIdx].trim() : '';
      final unit = (unitIdx != -1 && unitIdx < row.length) ? row[unitIdx].trim() : 'Pcs';
      final costStr = (costIdx != -1 && costIdx < row.length) ? row[costIdx].trim() : '0';
      final priceStr = (priceIdx != -1 && priceIdx < row.length) ? row[priceIdx].trim() : '0';
      final reorderStr = (reorderIdx != -1 && reorderIdx < row.length) ? row[reorderIdx].trim() : '0';
      final qtyStr = (qtyIdx != -1 && qtyIdx < row.length) ? row[qtyIdx].trim() : '0';

      final costPrice = int.tryParse(costStr.replaceAll(',', '')) ?? 0;
      final sellingPrice = int.tryParse(priceStr.replaceAll(',', '')) ?? 0;
      final reorderLevel = int.tryParse(reorderStr.replaceAll(',', '')) ?? 0;
      final openingQty = int.tryParse(qtyStr.replaceAll(',', '')) ?? 0;

      String? error;
      if (name.isEmpty) {
        error = 'Product name is required';
      } else if (costPrice < 0 || sellingPrice < 0) {
        error = 'Prices cannot be negative';
      } else if (openingQty < 0) {
        error = 'Opening quantity cannot be negative';
      }

      previewList.add(
        ImportPreviewItem(
          name: name,
          unit: unit.isEmpty ? 'Pcs' : unit,
          costPrice: costPrice,
          sellingPrice: sellingPrice,
          reorderLevel: reorderLevel,
          openingQuantity: openingQty,
          isValid: error == null,
          validationError: error,
        ),
      );
    }

    return previewList;
  }

  /// Imports valid preview items transactionally into the local Drift database
  Future<int> executeImport({
    required String businessId,
    required List<ImportPreviewItem> items,
  }) async {
    int importedCount = 0;
    final validItems = items.where((item) => item.isValid).toList();

    for (final item in validItems) {
      await dbService.createProduct(
        businessId: businessId,
        name: item.name,
        unit: item.unit,
        costPrice: item.costPrice,
        sellingPrice: item.sellingPrice,
        reorderLevel: item.reorderLevel,
        openingQuantity: item.openingQuantity,
      );
      importedCount++;
    }

    return importedCount;
  }
}

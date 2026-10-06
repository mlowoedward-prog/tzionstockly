import 'dart:io';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_service.dart';

class ExportService {
  final DatabaseService dbService;

  ExportService(this.dbService);

  /// Converts 2D list into RFC 4180 compliant CSV string
  static String convertToCsv(List<List<dynamic>> rows) {
    final buffer = StringBuffer();
    for (final row in rows) {
      final line = row.map((cell) {
        final str = cell?.toString() ?? '';
        if (str.contains(',') || str.contains('"') || str.contains('\n')) {
          return '"${str.replaceAll('"', '""')}"';
        }
        return str;
      }).join(',');
      buffer.writeln(line);
    }
    return buffer.toString();
  }

  /// Generates a CSV file from a 2D table array and opens share sheet
  Future<File> exportCsv({
    required String fileNamePrefix,
    required List<List<dynamic>> rows,
  }) async {
    final csvData = convertToCsv(rows);
    final dir = await getApplicationDocumentsDirectory();
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final filePath = '${dir.path}/${fileNamePrefix}_$dateStr.csv';
    final file = File(filePath);
    await file.writeAsString(csvData);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Exported $fileNamePrefix CSV',
    );
    return file;
  }

  /// Generates a PDF report document and opens share sheet
  Future<File> exportPdfReport({
    required String reportTitle,
    required String businessName,
    required String dateRangeText,
    required List<String> headers,
    required List<List<String>> dataRows,
  }) async {
    final pdf = pw.Document();
    final generatedDate = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(businessName, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                      pw.Text(reportTitle, style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Date Range: $dateRangeText', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('Generated: $generatedDate', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: dataRows,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1F3864)),
              cellHeight: 25,
              cellAlignments: {
                for (int i = 0; i < headers.length; i++) i: pw.Alignment.centerLeft,
              },
            ),
          ];
        },
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final safeTitle = reportTitle.toLowerCase().replaceAll(' ', '_');
    final filePath = '${dir.path}/stockly_${safeTitle}_$dateStr.pdf';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());

    await Share.shareXFiles(
      [XFile(file.path)],
      text: '$reportTitle PDF',
    );
    return file;
  }

  /// Full backup export of all products, partners, and movements to CSV
  Future<File> exportFullBackupCsv(String businessId) async {
    final products = await dbService.watchProductsWithStock(businessId).first;
    final partners = await dbService.watchPartners(businessId).first;

    final rows = <List<dynamic>>[];

    // Products section
    rows.add(['=== PRODUCTS ===']);
    rows.add(['ID', 'Name', 'SKU', 'Barcode', 'Unit', 'Cost Price (TZS)', 'Selling Price (TZS)', 'Reorder Level', 'Category', 'Quantity On Hand']);
    for (final p in products) {
      rows.add([
        p.id,
        p.name,
        p.sku ?? '',
        p.barcode ?? '',
        p.unit,
        p.costPrice,
        p.sellingPrice,
        p.reorderLevel,
        p.categoryName ?? '',
        p.quantityOnHand,
      ]);
    }

    rows.add([]);
    // Partners section
    rows.add(['=== PARTNERS (Suppliers & Customers) ===']);
    rows.add(['ID', 'Name', 'Type', 'Phone', 'Email']);
    for (final part in partners) {
      rows.add([part.id, part.name, part.type, part.phone ?? '', part.email ?? '']);
    }

    return exportCsv(fileNamePrefix: 'stockly_full_backup', rows: rows);
  }
}

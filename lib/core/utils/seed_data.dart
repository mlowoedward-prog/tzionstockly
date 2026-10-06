import '../database/database_service.dart';

class SeedDataService {
  final DatabaseService dbService;

  SeedDataService(this.dbService);

  Future<void> seedTanzanianShopData(String businessId) async {
    // Categories
    final catGroceries = await dbService.createCategory(businessId: businessId, name: 'Vyakula (Groceries)');
    final catBeverages = await dbService.createCategory(businessId: businessId, name: 'Vinywaji (Beverages)');
    final catPersonalCare = await dbService.createCategory(businessId: businessId, name: 'Usafi wa Mwili (Personal Care)');
    final catHousehold = await dbService.createCategory(businessId: businessId, name: 'Bidhaa za Nyumbani (Household)');
    final catGrains = await dbService.createCategory(businessId: businessId, name: 'Nafaka (Grains & Flour)');

    // Sample Suppliers
    await dbService.createPartner(
      businessId: businessId,
      name: 'Bakhresa Azam Wholesalers',
      type: 'supplier',
      phone: '+255 712 345 678',
    );
    await dbService.createPartner(
      businessId: businessId,
      name: 'MeTL Group Tanzania',
      type: 'supplier',
      phone: '+255 754 112 233',
    );

    // 30 Realistic Tanzanian Shop Products
    final products = [
      // Grains & Flour
      _SeedProduct('Sukari ya Azam 1kg', 'SKU-SUG-1', '600123456001', 'kg', 2800, 3200, 10, catGrains.id, 50),
      _SeedProduct('Unga wa Ngano Azam 2kg', 'SKU-WHT-2', '600123456002', 'bag', 4000, 4600, 15, catGrains.id, 40),
      _SeedProduct('Unga wa Sembe Super 5kg', 'SKU-MZE-5', '600123456003', 'bag', 9000, 10500, 8, catGrains.id, 25),
      _SeedProduct('Mchele wa Mbeya Grade 1 25kg', 'SKU-RCE-25', '600123456004', 'bag', 75000, 85000, 5, catGrains.id, 10),
      _SeedProduct('Mchele Supa Kyela 5kg', 'SKU-RCE-5', '600123456005', 'bag', 15000, 17500, 6, catGrains.id, 15),
      _SeedProduct('Maharagwe ya Mbeya 1kg', 'SKU-BNS-1', '600123456006', 'kg', 3000, 3600, 10, catGrains.id, 30),

      // Oils & Groceries
      _SeedProduct('Mafuta ya Kupikia Korie 5L', 'SKU-OIL-5', '600123456007', 'can', 28000, 32000, 5, catGroceries.id, 12),
      _SeedProduct('Mafuta ya Sundrop 1L', 'SKU-OIL-1', '600123456008', 'bottle', 6500, 7500, 10, catGroceries.id, 20),
      _SeedProduct('Chumvi ya Sea Salt 500g', 'SKU-SLT-500', '600123456009', 'pcs', 500, 700, 20, catGroceries.id, 100),
      _SeedProduct('Royco Mchuzi Mix 200g', 'SKU-ROY-200', '600123456010', 'pack', 2500, 3000, 10, catGroceries.id, 35),
      _SeedProduct('Tangawizi ya Kuponda 100g', 'SKU-GNG-100', '600123456011', 'pcs', 1000, 1300, 15, catGroceries.id, 25),
      _SeedProduct('Majani ya Chai Africafe 250g', 'SKU-TEA-250', '600123456012', 'pack', 3500, 4200, 8, catGroceries.id, 18),

      // Beverages
      _SeedProduct('Coca-Cola 350ml Crate (24)', 'SKU-COKE-CR', '600123456013', 'crate', 18000, 22000, 4, catBeverages.id, 8),
      _SeedProduct('Pepsi Soda 350ml Glass', 'SKU-PEP-350', '600123456014', 'bottle', 700, 1000, 24, catBeverages.id, 48),
      _SeedProduct('Maji ya Kilimanjaro 1.5L', 'SKU-WTR-1.5', '600123456015', 'bottle', 900, 1200, 12, catBeverages.id, 60),
      _SeedProduct('Maji ya Uhai 500ml Pack (12)', 'SKU-UHAI-PK', '600123456016', 'pack', 5000, 6500, 10, catBeverages.id, 20),
      _SeedProduct('Azam Malti Can 330ml', 'SKU-MLT-330', '600123456017', 'can', 1000, 1300, 20, catBeverages.id, 36),
      _SeedProduct('Juice ya Ceres 1L', 'SKU-CRS-1L', '600123456018', 'box', 4500, 5500, 6, catBeverages.id, 14),

      // Personal Care
      _SeedProduct('Sabuni ya Jamaa Cream 1kg', 'SKU-SOP-JAM', '600123456019', 'bar', 3000, 3600, 10, catPersonalCare.id, 40),
      _SeedProduct('Sabuni ya Imperial Leather 125g', 'SKU-SOP-IMP', '600123456020', 'pcs', 1800, 2300, 15, catPersonalCare.id, 30),
      _SeedProduct('Dawa ya Meno Whitedent 150g', 'SKU-WHT-150', '600123456021', 'pcs', 2000, 2500, 12, catPersonalCare.id, 25),
      _SeedProduct('Mafuta ya Vaseline Jelly 100ml', 'SKU-VAS-100', '600123456022', 'jar', 2500, 3200, 8, catPersonalCare.id, 18),
      _SeedProduct('Mafuta ya Baby Care 200ml', 'SKU-BCR-200', '600123456023', 'bottle', 3500, 4500, 5, catPersonalCare.id, 12),
      _SeedProduct('Shampoo ya Sunsilk 200ml', 'SKU-SHM-200', '600123456024', 'bottle', 4000, 5000, 5, catPersonalCare.id, 10),

      // Household Products
      _SeedProduct('Sabuni ya Unga Foma 1kg', 'SKU-FOM-1KG', '600123456025', 'pack', 3500, 4200, 10, catHousehold.id, 25),
      _SeedProduct('Sabuni ya Unga Omo 500g', 'SKU-OMO-500', '600123456026', 'pack', 2200, 2800, 15, catHousehold.id, 30),
      _SeedProduct('Kiberiti cha Farasi (Box of 10)', 'SKU-MTH-10', '600123456027', 'box', 1000, 1500, 20, catHousehold.id, 50),
      _SeedProduct('Viberiti vya Gesi (Gas Lighter)', 'SKU-LGT-01', '600123456028', 'pcs', 1200, 1800, 10, catHousehold.id, 15),
      _SeedProduct('Dawa ya Mbu Doom Spray 300ml', 'SKU-DOM-300', '600123456029', 'can', 7000, 8500, 5, catHousehold.id, 8),
      _SeedProduct('Tishu ya Flora Soft 4-Pack', 'SKU-TSH-4PK', '600123456030', 'pack', 2800, 3500, 10, catHousehold.id, 22),
    ];

    for (final p in products) {
      await dbService.createProduct(
        businessId: businessId,
        name: p.name,
        sku: p.sku,
        barcode: p.barcode,
        unit: p.unit,
        costPrice: p.costPrice,
        sellingPrice: p.sellingPrice,
        reorderLevel: p.reorderLevel,
        categoryId: p.categoryId,
        openingQuantity: p.openingQuantity,
      );
    }
  }
}

class _SeedProduct {
  final String name;
  final String sku;
  final String barcode;
  final String unit;
  final int costPrice;
  final int sellingPrice;
  final int reorderLevel;
  final String categoryId;
  final int openingQuantity;

  _SeedProduct(
    this.name,
    this.sku,
    this.barcode,
    this.unit,
    this.costPrice,
    this.sellingPrice,
    this.reorderLevel,
    this.categoryId,
    this.openingQuantity,
  );
}

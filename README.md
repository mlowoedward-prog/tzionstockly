# Tzion Stockly

**Offline-First Inventory Management & Analytics App for Small Shops in Tanzania.**

Tzion Stockly is built with Flutter, Material 3, Riverpod, GoRouter, Drift (local SQLite DB), and Supabase (cloud backup & cross-device sync).

---

## Key Features

- **100% Offline First:** All UI reads and writes execute against local Drift SQLite database. Zero network dependency for daily shop operations.
- **Append-Only Stock Ledger:** Stock quantities calculated via `SUM(signed stock_movements)`.
- **Role-Based Access Control:** `Owner`, `Manager`, and `Staff` roles with cost data protection (staff devices cannot access cost prices or gross profit data).
- **Multi-Device Sync Engine:** Idempotent FIFO push queue, transactional pull, last-write-wins conflict resolution, and automatic connectivity triggers.
- **Reports & Analytics:** Dashboard KPIs, Gross Profit (`Sales - COGS`), Stock Valuation, Slow Movers, PDF report exports, and RFC 4180 CSV exports.
- **Data Backup & Restore:** CSV backup exporter and transactional CSV catalog/stock importer.
- **Swahili & English Localization:** Dynamic language switcher in Settings (`app_en.arb`, `app_sw.arb`).

---

## Setup & Running Locally

1. **Clone Repository:**
   ```bash
   git clone https://github.com/tzion/tzion_stockly.git
   cd tzion_stockly
   ```

2. **Install Dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run Unit & Widget Tests:**
   ```bash
   flutter test
   ```

4. **Run Application in Debug Mode:**
   ```bash
   flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co --dart-define=SUPABASE_ANON_KEY=your-anon-key
   ```

---

## Release Build Instructions

### Android Release APK
To build a production-ready signed Android APK:
```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

### Android App Bundle (AAB for Google Play Store)
To build an Android App Bundle for Google Play Store deployment:
```bash
flutter build appbundle --release \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

---

## Keystore Setup & Security Guide

1. **Generate Release Keystore:**
   ```bash
   keytool -genkey -v -keystore android/app/upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. **Configure Key Properties:**
   Create `android/key.properties` (added to `.gitignore`):
   ```properties
   storePassword=YOUR_STORE_PASSWORD
   keyPassword=YOUR_KEY_PASSWORD
   keyAlias=upload
   storeFile=upload-keystore.jks
   ```
3. **NEVER** commit `key.properties` or `upload-keystore.jks` to Git repository. Backup the keystore file securely in offline storage.

---

## Continuous Integration & Supabase Keep-Alive

- **GitHub Actions CI (`.github/workflows/ci.yml`):** Runs `flutter analyze` and `flutter test` automatically on every push or pull request.
- **Supabase Keep-Alive Workflow (`.github/workflows/keepalive.yml`):** Automatically pings `<SUPABASE_URL>/rest/v1/health_check` every 2 days to prevent Supabase Free Tier project auto-pausing.

---

## Play Store Readiness & Data Safety Declaration

- **App Package Name:** `com.tzion.tzion_stockly`
- **Monetization Declaration:** No in-app purchases, no subscriptions, no ads, no payment gateway packages.
- **Data Safety Form Answers:**
  - Data collected: User Account Email (Auth), Business Inventory & Sales ledger.
  - Data encryption: In transit via HTTPS/TLS 1.3, locally via encrypted secure storage.
  - User rights: Full data deletion & CSV backup export supported.

---

## License & Operational Support

For pilot onboarding assistance and documentation, refer to [`docs/PILOT_CHECKLIST.md`](file:///d:/tzionstockly/docs/PILOT_CHECKLIST.md).

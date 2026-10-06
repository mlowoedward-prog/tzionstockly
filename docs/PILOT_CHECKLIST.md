# Tzion Stockly: Shop Pilot Testing Checklist & Field Guide

This document outlines the step-by-step pilot testing routine for deploying **Tzion Stockly** in small retail shops (maduka) in Tanzania.

---

## 1. Pre-Pilot Setup Checklist

- [ ] **Device Readiness:** Ensure Android device has at least 15% free storage space and Android 8.0+ installed.
- [ ] **App Installation:** Install signed release APK with Supabase parameters (`--dart-define`).
- [ ] **First Launch & Language:** Open Tzion Stockly. Set preferred language (English or Kiswahili) in Settings.
- [ ] **Initial Account & Shop Setup:**
  - Owner creates account and registers Shop Name (e.g. *Duka la Mwenge*).
  - Verify seed items or import existing product catalog via **CSV Backup Import**.
- [ ] **Staff Invitation:** Invite shop managers and sales staff via **Settings > Shop Team & Roles**. Assign appropriate roles (`Staff`, `Manager`, `Owner`).

---

## 2. Daily Pilot Routine (2-Week Test Plan)

### Morning Opening (Asubuhi)
1. **Connectivity Check:** Open app. Inspect top **Sync Status Chip** (`Synced` / `Offline`). Confirm local app functions smoothly offline.
2. **Stock Audit:** Review **Needs Restocking** alert list on Dashboard. Note low-stock items.

### Operations (Mchana)
1. **Record Sales & Purchases:**
   - Tap **Stock** tab.
   - Select operation: **Sale**, **Purchase (Stock In)**, or **Adjustment**.
   - Scan barcode or search product name.
   - Enter quantity and submit. Verify instantaneous update to quantity-on-hand.
2. **Offline Resilience Test:**
   - Turn off Wi-Fi & Cellular Data (Airplane Mode).
   - Perform 5 sales and 2 stock entries. Verify "Saved offline" feedback.
   - Re-enable connectivity. Tap **Sync Status Chip > Sync Now** and verify pending queue count drops to 0.

### Evening Closing (Jioni)
1. **Daily Financial Review:**
   - Tap **Reports** tab. Select **Today** date filter.
   - Review **Sales Summary** and **Gross Profit (Revenue - COGS)**.
   - Verify numbers match physical cash drawer / mobile money ledger.
2. **Full Backup Export:**
   - Go to **Settings > Backup Export (CSV)**.
   - Save local backup file `stockly_backup_YYYY-MM-DD.csv`.

---

## 3. Pilot Feedback & Incident Log Template

| Date | Time | Feature / Screen | User Role | Description of Issue / Observation | Resolution / Action Taken |
|------|------|-------------------|-----------|-------------------------------------|---------------------------|
|      |      |                   |           |                                     |                           |
|      |      |                   |           |                                     |                           |
|      |      |                   |           |                                     |                           |

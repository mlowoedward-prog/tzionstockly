# TzionStockly: Offline-First Inventory Management System
## Technical Implementation Document & Architecture Specification

### 1. Executive Summary & Architecture Overview
TzionStockly is an offline-first inventory management application designed for retail and warehouse environments where network connectivity is inconsistent. The system operates on a **Local-First (Zero-Latency)** paradigm: all stock mutations execute against an embedded local database immediately, while an asynchronous background synchronization engine coordinates with Supabase (PostgreSQL) when connectivity is available.

```
┌─────────────────────────────────────────────────────────────┐
│                      TzionStockly Client                    │
│                                                             │
│   ┌─────────────────────┐         ┌─────────────────────┐   │
│   │   Admin Interface   │         │   Staff Terminal    │   │
│   │ (Check In/Out, P&L, │         │ (Check Out Only,    │   │
│   │  Excel Bulk, Users) │         │  Stock Verification)│   │
│   └──────────┬──────────┘         └──────────┬──────────┘   │
│              └────────────┐     ┌────────────┘              │
│                           ▼     ▼                           │
│              ┌───────────────────────────────┐              │
│              │    Local Embedded Database    │              │
│              │    (Isar / SQLite / Dexie)    │              │
│              └──────────────┬────────────────┘              │
│                             │                               │
│                             ▼                               │
│              ┌───────────────────────────────┐              │
│              │    Offline Outbox Queue       │              │
│              └──────────────┬────────────────┘              │
└─────────────────────────────┼───────────────────────────────┘
                              │ Auto-Sync on Network Reconnect
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Supabase Cloud                         │
│                                                             │
│   ┌───────────────┐  ┌──────────────────┐  ┌────────────┐   │
│   │ Supabase Auth │  │ PostgreSQL + RLS │  │ Storage /  │   │
│   │ (JWT / Roles) │  │ (Delta Triggers) │  │ Edge Funcs │   │
│   └───────────────┘  └──────────────────┘  └────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

### 2. Technology Stack & Library Selection
- **Frontend / Framework:** Flutter (Dart) for compiled mobile/desktop builds, or Modern Web (React / Vite PWA / Single-File Progressive UI).
- **Local Persistence (Client-Side):**
  - Flutter: `drift` / `sqflite` / `isar`
  - Web: `dexie` / `IndexedDB` / `localStorage` local cache
- **Cloud Backend & Database:** Supabase (PostgreSQL 15+, Supabase Auth, Row Level Security, Realtime).
- **Analytics Engine:** Client-side computation rendered via `fl_chart` (Flutter) or `Chart.js` (Web).
- **Spreadsheet Processing:** `excel` / `csv` (Dart) or `xlsx` / `SheetJS` (Web) for direct offline binary parsing.
- **Connectivity Monitor:** `connectivity_plus` (Flutter) or `navigator.onLine` window listeners (Web).

---

### 3. Supabase Database Schema (PostgreSQL DDL)
The migration file `supabase/migrations/00004_atomic_stock_mutation_and_profiles.sql` defines:
- `profiles` table linked to `auth.users` with `user_role` (`admin`, `staff`).
- `products` catalog table with TZS currency fields (`cost_price_tzs`, `selling_price_tzs`, `stock_quantity`, `min_threshold`).
- `stock_transactions` audit log.
- `process_stock_mutation` atomic stored procedure with permission checks and quantity validation.
- Row Level Security (RLS) policies and `handle_new_user()` trigger.

---

### 4. Offline Synchronization Engine (Outbox Architecture)
To guarantee that inventory adjustments are preserved when offline, all client operations interact exclusively with the local database.

#### Local Data Collections
- `products_cache`: Mirror of the remote products table.
- `sync_outbox`: FIFO event queue storing unresolved server mutations.

#### Outbox Record Specification
```json
{
  "client_mutation_id": "c1f7b770-9f22-4809-9f7a-8fce9b8e8890",
  "endpoint": "rpc/process_stock_mutation",
  "payload": {
    "p_product_id": "a9d7e324-118c-4f81-8d2b-635293414902",
    "p_user_id": "33b2a249-fceb-4179-8804-09ad695b21aa",
    "p_type": "CHECK_OUT",
    "p_quantity": 3,
    "p_unit_price_tzs": 45000.00,
    "p_notes": "Retail Counter POS",
    "p_device_created_at": "2026-11-07T10:45:00.000Z"
  },
  "status": "PENDING", 
  "attempts": 0,
  "created_at": 1731000000
}
```

#### Sync Resolution Logic
1. **Mutation Ingestion:** On user action, write updated stock to `products_cache` immediately. Append payload to `sync_outbox`.
2. **Connectivity Trigger:** Listen to connectivity state changes. When connection status shifts to ONLINE, trigger the sync runner.
3. **Queue Replay:**
   - Read `sync_outbox` ordered by `created_at ASC`.
   - Post each payload to Supabase RPC `process_stock_mutation`.
   - On HTTP 200 OK, remove item or mark status `SYNCED`.
   - If a conflict occurs (e.g., negative stock constraint violation), mark `status: "CONFLICT"`, preserve the record, and flag for Admin review.
4. **Master Sync:** Following queue drain, fetch all products where `updated_at > last_sync_timestamp` and merge into `products_cache`.

---

### 5. Role-Based Access Control (RBAC) & Screen Architecture

```
                                  ┌───────────────┐
                                  │  Auth Gateway │
                                  └───────┬───────┘
                                          │
                    ┌─────────────────────┴─────────────────────┐
                    ▼                                           ▼
          [Role == 'admin']                           [Role == 'staff']
    ┌───────────────────────────┐               ┌───────────────────────────┐
    │      Admin Dashboard      │               │   Staff Terminal (POS)    │
    ├───────────────────────────┤               ├───────────────────────────┤
    │ • Stock In (+ units)      │               │ • Check Out Only          │
    │ • Stock Out (- units)     │               │ • Search & Verify Stock   │
    │ • Cost Price & Margin TZS │               │ • Cost Price HIDDEN       │
    │ • Asset Valuation TZS     │               │ • Margin Metrics HIDDEN   │
    │ • Excel / CSV Bulk Import │               │ • Stock-In RESTRICTED     │
    │ • 7-Day Velocity Chart    │               │ • Pending Outbox View     │
    │ • Manage Users & PINs     │               │ • Direct WhatsApp Receipt │
    └───────────────────────────┘               └───────────────────────────┘
```

#### Screen Routing Specifications
- **Login Route (`/login`):** Role-selector segmented control, Email/PIN authentication input, and offline session cache retrieval.
- **Admin Hub (`/admin/dashboard`):**
  - Metrics Grid: Total Inventory Value (TZS), Estimated Retail Profit (TZS), Low Stock Counter.
  - Stock Flow Chart: 7-day bar/line chart tracking incoming vs outgoing unit volumes.
  - Inventory Table: Columns for SKU, Product Name, Category, Stock Level, Cost Price (TZS), Selling Price (TZS), and dual Action buttons (+ IN / - OUT).
- **Staff Hub (`/staff/pos`):**
  - Simplified product card grid with instant touch targets.
  - Real-time search by SKU or Item Name.
  - Quantity stepper with single "Complete Check Out" action.
  - Direct WhatsApp Receipt generation.
  - Absolute omission of cost price and profit columns.

---

### 6. Excel / CSV Bulk Ingestion Engine
The ingestion pipeline runs entirely in-memory on the client to allow bulk stock imports without an internet connection.

#### Spreadsheet Column Contract
| Canonical Key | Accepted Aliases | Data Type | Validation Rules |
| :--- | :--- | :--- | :--- |
| `sku` | Item Code, Code, Barcode | String | Unique, non-empty, auto-trimmed |
| `name` | Product Name, Item, Title | String | Non-empty |
| `category` | Group, Department | String | Default to "General" if blank |
| `stockQty` | Qty, Quantity, Initial Stock, Stock | Integer | Integer $\ge 0$ |
| `min_threshold` | Alert Level, Min Qty, Min Stock | Integer | Integer $\ge 1$, default 5 |
| `cost_price_tzs` | Cost, Cost Price, Buying Price | Numeric | Decimal $\ge 0.00$ |
| `selling_price_tzs` | Price, Retail Price, Selling Price | Numeric | Must be $\ge$ `cost_price_tzs` |

---

### 7. Brand Design System & Color Tokens
Purple, orange, and white brand identity:
```css
:root {
  /* Core Brand Colors */
  --tzion-purple-primary:   #4c1d95; /* Deep Purple */
  --tzion-purple-accent:    #7c3aed; /* Electric Purple */
  --tzion-purple-glow:      #8b5cf6;
  --tzion-orange-primary:   #ea580c; /* Deep Vibrant Orange */
  --tzion-orange-accent:    #f97316; /* Electric Orange */
  --tzion-orange-light:     #fed7aa;

  /* Neutral Dark Theme */
  --dark-bg-base:           #0d0b14;
  --dark-surface:           #161224;
  --dark-border:            #2e244d;
  --dark-text-primary:      #f8fafc;
  --dark-text-secondary:    #94a3b8;

  /* Neutral Light Theme */
  --light-bg-base:          #f8f6fc;
  --light-surface:          #ffffff;
  --light-border:           #e5def0;
  --light-text-primary:     #1e1b4b;
  --light-text-secondary:   #64748b;

  /* Functional Badges */
  --color-success:          #10b981;
  --color-warning:          #f59e0b;
  --color-danger:           #ef4444;
}
```

---

### 8. Implementation Verification Checklist
- [x] **Step 1: Supabase Configuration**
  - Migration script created: `00004_atomic_stock_mutation_and_profiles.sql`
  - Tables: `profiles`, `products`, `stock_transactions`
  - Stored procedure: `process_stock_mutation`
  - RLS policies configured & user trigger `handle_new_user()` deployed.
- [x] **Step 2: Client Storage & Sync Module**
  - Local database cache schema (`products_cache` & `sync_outbox`)
  - CRUD operations and outbox record specification conforming to `rpc/process_stock_mutation`
  - Background queue runner with retry logic and conflict handling.
- [x] **Step 3: Authentication & Role Guarding**
  - `/login` with Admin and Staff role tabs.
  - Role-based view switching & route protection (`/staff/pos` and `/admin/dashboard`).
- [x] **Step 4: Admin Dashboard & Financial Tracking**
  - TZS currency formatting throughout all cards, tables, and dialogs.
  - Dual action "+ Check In" and "- Check Out" dialogs with stock validation.
  - 7-day stock flow bar/line chart.
- [x] **Step 5: Staff POS Terminal**
  - Rapid touch card checkout with real-time stock verification.
  - Cost price and profit metrics completely omitted.
  - Direct WhatsApp receipt generator.
- [x] **Step 6: Excel Bulk Ingestion**
  - Flexible column aliases and validation parsing.
  - Staging preview table with validation badges.
  - `TzionStockly_Template.xlsx` download generator.
- [x] **Step 7: Theming & Visual Polish**
  - Purple (`#4c1d95`), Orange (`#ea580c`), and White design tokens applied.
  - Dynamic Light/Dark mode switcher and Desktop/Mobile responsive shells.


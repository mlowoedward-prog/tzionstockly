# Tzion Stockly: Full Antigravity Prompt Pack

Offline-first inventory and analysis app. Flutter (Android first) + Drift (local SQLite) + Supabase (Free project for testing).

## How to use this pack

1. Put your implementation document in `docs/PROJECT_CONTEXT.md` and your Stitch screens in `docs/design/` before starting.
2. Paste **Prompt A (Working Rules)** at the start of the project, and save it as `docs/AGENT_RULES.md` so you can say "follow docs/AGENT_RULES.md" in later prompts.
3. Run the phase prompts **in order**, one at a time. Do not move on until the previous phase passes analysis, tests and a device check.
4. Commit to Git after every finished phase.
5. Package APIs change often. Every prompt tells the agent to check current documentation instead of relying on memory. Review the agent's plan before approving big changes.

---

## Prompt A: Working Rules (paste first, save as docs/AGENT_RULES.md)

```
You are helping me build "Tzion Stockly", an offline-first inventory management and analysis app for small shops in Tanzania. Follow these rules for the whole project.

PROJECT FACTS
- Flutter (Dart), Android first. Material 3. State management: Riverpod. Navigation: go_router. Local database: Drift (SQLite). Cloud backend: Supabase (added in Phase 3). Languages: English and Swahili.
- Read docs/PROJECT_CONTEXT.md before any task. Follow its architecture, database design, stock ledger and sync design. If something conflicts with it, stop and ask me.
- UI designs are in docs/design/. Match them closely, using Flutter's Material 3 widgets. 

NON-NEGOTIABLE RULES
1. Offline first: the UI reads and writes only the local database. Screens never wait for the network.
2. Stock is a ledger: quantity on hand = SUM of signed stock_movements. Movements are append-only. Corrections use a new adjustment movement. Never edit a quantity directly.
3. Every synced table has: id (UUID text generated on the device), business_id, created_at, updated_at, deleted_at (soft delete). Local tables also have a synced flag.
4. No payments, no in-app purchases, no subscriptions, no payment or billing packages. Sales and purchases are records only.
5. Layering: screens -> Riverpod providers -> repositories -> DAOs. Only the sync engine talks to Supabase for data. Business logic lives in the domain layer so it can be unit tested without Flutter.
6. Never hard-code secrets. Supabase URL and anon key come from --dart-define. Never use or ship the service-role key.
7. All user-facing text goes in the ARB files (English and Swahili). No hard-coded strings in widgets.
8. Money is shown as TZS with thousands separators. Store money as integers (whole shillings) or a decimal type, never floating point.

HOW TO WORK
- Add dependencies with `flutter pub add` so versions are current. Check the current official docs for any package whose setup you are unsure about.
- Do not add packages I did not ask for. Tell me before adding any extra package.
- Work in small steps. After each task run `flutter analyze` and `flutter test` and fix problems.
- Show me a plan before large changes, and list every file you created or changed at the end.
- Prove it works: run the app on my connected Android device and give me screenshots of the finished screens.
- If a command would delete data, change a database that already has data, or touch my Supabase project, stop and ask for approval first.
- If you are unsure about a requirement, ask me instead of guessing.

END EVERY TASK WITH
1. What was done  2. Files changed  3. Test and analyze results  4. Screenshots  5. Known problems or decisions I need to make.
```

---

## Prompt 0: Project Setup

```
Follow docs/AGENT_RULES.md. Read docs/PROJECT_CONTEXT.md first.

GOAL: Create the project skeleton and a running app shell. No features yet.

TASKS
1. Run `flutter create` for a project named tzion_stockly with organization id com.tzion and Android as the main platform. Initialize Git and add a proper .gitignore.
2. Create this feature-first structure:
   lib/app/ (router, theme, app shell)
   lib/core/database/, lib/core/sync/, lib/core/network/, lib/core/utils/
   lib/features/{auth,products,stock,partners,sales,dashboard,reports,settings}/ each with data/, domain/, presentation/
   lib/l10n/
   test/ and integration_test/
3. Add dependencies using `flutter pub add`: flutter_riverpod, go_router, drift, drift_flutter, uuid, intl, fl_chart, mobile_scanner, path_provider. Add dev dependencies: drift_dev, build_runner, flutter_lints, mocktail. Check Drift's current setup documentation and configure it correctly.
4. Theme (Material 3): primary deep navy #1F3864, secondary teal #14B8A6, background #F5F7FA, white cards with 12px radius and soft shadows, success green, warning amber, error red. Provide light and dark themes. Use Inter (via google_fonts) or Roboto.
5. Localization: set up flutter_localizations and intl with app_en.arb and app_sw.arb. Add the keys for the five navigation labels (Home, Products, Stock, Reports, More) in English and Swahili (Mwanzo, Bidhaa, Hisa, Ripoti, Zaidi).
6. App shell with go_router: bottom navigation bar on phones (Home, Products, Stock, Reports, More) and a navigation rail or sidebar when the screen width is 900 or more (for tablets and the web/desktop version later). Each tab shows a placeholder screen.
7. Add a small SyncStatusChip widget (states: Synced, Syncing, Offline, Pending) with a mock state for now, shown on the Home screen.
8. Create a README.md with setup and run instructions, and a docs/ folder note that lists where the context and design files are.
9. Do NOT add Supabase, payment or in-app purchase packages.

VERIFY
- `flutter analyze` has no issues and `flutter test` passes (add one widget test that the shell renders all five tabs).
- Run on my connected Android device and show screenshots of the light theme, the dark theme and the Swahili labels.
- Make the first Git commit: "chore: project skeleton".
```

---

## Prompt 1: Local Core (database, inventory, partners, stock, sales records)

```
Follow docs/AGENT_RULES.md. Read the database design and stock ledger sections of docs/PROJECT_CONTEXT.md and the screens in docs/design/.

GOAL: A fully working offline inventory core. No Supabase yet.

1. DATABASE (Drift)
- Tables: businesses, categories, products, partners (type: supplier or customer), stock_movements, sync_queue, sync_state.
- All ids are UUID text generated on the device. Synced tables have business_id, created_at, updated_at, deleted_at, and a local synced flag.
- products: name, sku, barcode, unit, cost_price, selling_price, reorder_level, category_id, image_path.
- stock_movements: product_id, type (purchase, sale, adjustment, return, damage), signed quantity, unit_cost, unit_price, partner_id, note, created_by, occurred_at. Append-only: no update or delete operations in the DAO.
- Create a default local business on first run and use its id as business_id for now.
- Add indexes: (business_id, updated_at) on synced tables, products(barcode), products(sku), stock_movements(product_id, occurred_at).
- Add a database view or query that returns each product with quantity_on_hand = SUM(signed quantity) and a stock status (in stock, low, out) based on reorder_level.
- Write the first Drift schema version and set up migrations so later changes do not wipe data.
- Every local write also inserts a row into sync_queue (table_name, record_id, operation, payload) so Phase 3 can push it. Do this inside the same transaction as the write.

2. DOMAIN AND DATA
- Repositories and Riverpod providers for categories, products, partners and stock movements (streams so the UI updates automatically).
- A StockService in the domain layer: record purchase, sale, return, damage and adjustment. Sales must reduce stock; block or warn when a sale would make stock negative (make this a setting, default warn).
- Soft delete: archiving a product sets deleted_at; archived items are hidden but their history stays.

3. SCREENS (match docs/design/)
- Products list: search, category filter chips, sort, stock status badges, barcode scan button.
- Product detail: info, quantity on hand, movement history.
- Add/Edit product: name, category, SKU, barcode (scan), unit, cost, price, opening quantity (creates an opening purchase movement), reorder level, photo from camera or gallery (compress and limit size).
- Stock entry screen: segmented control for Stock In, Stock Out, Adjustment, Sale; search or scan to add items; quantity steppers; optional supplier or customer; note; Record button. No payment buttons.
- Partners: list and add/edit for suppliers and customers.
- Show "Saved offline" confirmation after saving.

4. TESTS
- Unit tests: quantity on hand calculation, status thresholds, negative stock rule, soft delete, sync_queue entry created for each write.
- Widget tests for the add-product form validation (name required, prices not negative).

5. SEED DATA
- Add a debug-only seed option with 30 realistic Tanzanian shop products (Sugar 1kg, Cooking Oil 5L, Rice 25kg, Soda Crate, Soap Bar, Maize Flour 2kg, etc.) priced in TZS.

VERIFY
- analyze and tests pass. Run on my Android device and give screenshots of products list, add product, product detail with history, and stock entry. Demonstrate in airplane mode that everything works.
- Commit: "feat: local inventory core".
```

---

## Prompt 2: Dashboard, Reports and Export

```
Follow docs/AGENT_RULES.md. Read the analytics section of docs/PROJECT_CONTEXT.md and the Dashboard and Reports designs in docs/design/.

GOAL: Useful analysis that works fully offline.

1. DASHBOARD
- KPI cards: Total stock value (SUM of quantity x cost), Sales today, Low-stock count, Out-of-stock count.
- Line chart: sales for the last 7 days. Bar chart: top 5 products by quantity sold this month. "Needs restocking" list with photo, name, quantity left and a progress bar vs reorder level.
- Tapping a KPI opens the matching filtered list or report.

2. REPORTS (date range: Today, Week, Month, Custom)
- Sales summary by day, week or month.
- Gross profit = sales revenue minus cost of goods sold for the period (use the unit_cost recorded on each movement).
- Stock valuation by product and category.
- Top sellers (by quantity or revenue).
- Slow movers: products with no sales in N days (setting, default 30).
- Low stock report.
- Movement history, filterable by product, type, user and date.

3. IMPLEMENTATION RULES
- All numbers come from SQL aggregates in Drift queries (not by loading every row into memory). Add indexes where needed.
- Put calculations in the domain layer with unit tests, including edge cases: no sales, returns, adjustments, negative quantities, products archived mid-period.
- Paginate long tables. Use loading and empty states with clear messages.
- Use fl_chart for charts, readable in bright light, with accessible labels.

4. EXPORT
- CSV export for every report. PDF export with the business name, report title, date range and generated date. Use the csv, pdf, printing and share_plus packages (check current versions and APIs).
- Export file names like stockly_sales_2026-10.csv.
- Add a "Backup export (all data as CSV)" action in Settings that exports products, partners and movements.

5. TESTS AND PERFORMANCE
- Seed 5,000 products and 50,000 movements in a test and confirm the dashboard and the main reports load in under 2 seconds on my device. Report the real numbers.

VERIFY
- analyze and tests pass; screenshots of dashboard, each report, and an exported PDF; compare a few report totals against manual calculations and show the check.
- Commit: "feat: dashboard, reports, export".
```

---

## Prompt 3: Supabase Backend, Auth and Sync Engine

```
Follow docs/AGENT_RULES.md. Read the sync, security and hosting sections of docs/PROJECT_CONTEXT.md carefully. This is the hardest phase, so first show me a written plan and wait for my approval before changing anything.

I will create the Supabase project myself (Free tier) and give you the URL and anon key through --dart-define. Never ask me to paste the service-role key into the app or chat. Do not run SQL against my cloud project without my approval; write migrations as files in supabase/migrations/ and tell me how I apply them.

PART 1: SUPABASE SCHEMA (as migration files)
- Tables mirroring the local schema: businesses, business_members (user_id, business_id, role: owner, manager, staff), categories, products, partners, stock_movements.
- Every table has business_id, created_at, updated_at, deleted_at.
- A trigger that sets updated_at on the server for every insert and update (so conflict decisions use server time, not device clocks).
- Row Level Security enabled on every table. Policies: a user can read and write only rows whose business_id belongs to a business they are a member of. Stock movements: insert and select only (no update or delete).
- A health_check table with one row and a select policy for the anon role, used by the keep-alive ping.
- Indexes on (business_id, updated_at) and stock_movements(product_id, occurred_at).

PART 2: AUTH IN THE APP
- Add supabase_flutter. Read the URL and anon key from --dart-define (SUPABASE_URL, SUPABASE_ANON_KEY). Never hard-code them.
- Screens: sign up, login, password reset, create business (first-time) or join business.
- The app must keep working offline for a user who is already logged in. Store the session securely (flutter_secure_storage if needed). Allow using the app in "local only" mode before login.
- On first login, attach existing local data to the new business and queue it for upload.

PART 3: SYNC ENGINE (lib/core/sync/)
- Push: read sync_queue in creation order, send batched upserts by UUID grouped by table, on success remove the queue item and set synced = true; on failure increment attempts, store last_error, retry with exponential backoff. Retries must be idempotent (no duplicates).
- Pull: per table, fetch rows where updated_at > last_pulled_at (including soft-deleted rows), apply in one transaction, skip remote rows older than a pending local change for the same record, save last_pulled_at only after the transaction commits.
- Conflicts: products, categories, partners use last write wins by server updated_at; stock_movements are append-only; a delete wins over an older edit.
- Triggers: app start and resume, connectivity regained (connectivity_plus), after local writes (debounced), periodic background sync (workmanager), and a manual "Sync now".
- Replace the mock SyncStatusChip with real state: Synced, Syncing, Offline, Pending (with count), Error (tap to see the cause and Retry). Show a small per-record indicator on lists.
- Sync failures must never block the UI.

PART 4: KEEP-ALIVE (Free tier)
- Create .github/workflows/keepalive.yml that runs every 2 days (and manually) and calls <SUPABASE_URL>/rest/v1/health_check?select=id&limit=1 with the apikey and Authorization headers from repository secrets. The job should fail on a non-200 response.

TESTS
- Unit tests with a fake remote: push retry and idempotency, pull ordering, last_pulled_at only advanced on commit, conflict rules, soft-delete propagation.
- Document manual two-device tests: create offline on A, edit on B, reconnect both, kill the app mid-sync, large first sync.

VERIFY
- analyze and tests pass; give me exact steps to apply migrations and run with --dart-define; screenshots of login, create business, and the sync status in each state; a short list of risks you see.
- Commit in small steps: "feat: supabase schema", "feat: auth", "feat: sync engine", "ci: keep-alive".
```

---

## Prompt 4: Roles, Alerts, Settings and Polish

```
Follow docs/AGENT_RULES.md. Read the security and roles sections of docs/PROJECT_CONTEXT.md.

GOAL: Complete the MVP feature set.

1. ROLES AND PERMISSIONS (Owner, Manager, Staff)
- Staff: can record sales and stock movements, limited product editing, cannot see cost prices, profit or full reports, cannot manage users, cannot archive records.
- Manager: all of the above plus products, costs, reports, archiving. Owner: everything plus managing users and roles.
- Enforce in the UI and in the database. Hiding costs only in the UI is not enough, because synced data would still be on a staff phone. Before coding, propose a design (for example moving cost data to a separate table with RLS limited to owner and manager) and wait for my approval.
- Screen for owners to invite users by email and change roles.

2. LOW-STOCK ALERTS
- Local notifications (flutter_local_notifications) when an item reaches its reorder level, working offline. Group them into one daily summary option in Settings. Optional push notifications are a later phase.

3. SETTINGS
- Language (English / Swahili), theme, currency label, default negative-stock behaviour, slow-mover days, PIN or biometric app lock (local_auth), sync controls (last synced, pending count, Sync now), Backup export, account and logout.

4. LOCALIZATION AND UX POLISH
- Complete Swahili translations for every screen. Check for overflow with longer Swahili labels.
- Empty states, error states, loading skeletons, confirmation dialogs for destructive actions, undo snackbars where safe.
- Accessibility: touch targets of at least 48dp, contrast, font scaling up to 130% without breaking layouts.
- Performance pass on a low-end Android device profile: list virtualization, image caching, no jank on the product list.

5. TESTS
- Permission tests for each role, alert threshold tests, app lock tests where feasible.

VERIFY
- analyze and tests pass; screenshots as Owner, Manager and Staff showing the differences; show that a staff account cannot read cost data from the backend.
- Commit: "feat: roles, alerts, settings, polish".
```

---

## Prompt 5: Testing, Hardening and Pilot Readiness

```
Follow docs/AGENT_RULES.md. GOAL: find and fix problems before I use the app in my shop.

1. Review the whole codebase against docs/PROJECT_CONTEXT.md and docs/AGENT_RULES.md. Produce a report of every rule that is violated (offline-first, ledger, secrets, hard-coded strings, layering, payments) with file and line, then fix them.
2. Write integration tests (integration_test/) for these flows: first-run setup, add product, stock in, sale, low-stock alert, report totals, export, offline create then sync, login on a second device.
3. Write sync stress tests: 5,000 products and 50,000 movements first sync; interrupted sync; duplicate pushes; two devices editing the same product; clock skew on a device.
4. Data safety: confirm a database migration keeps existing data; confirm backup export can be re-imported (add a restore-from-CSV feature if it is missing, with validation and a preview before importing).
5. Error handling: no unhandled exceptions; friendly messages; a local log screen (Settings > Diagnostics) that records sync errors without any personal data or keys.
6. Security review: confirm RLS blocks cross-business access (write tests with two test businesses), confirm no secrets in the repo or build, confirm HTTPS only.
7. Produce docs/PILOT_CHECKLIST.md for testing in my own shop: setup steps, a 2-week test plan, daily stock-count routine, and a feedback log template.

VERIFY
- All tests pass; give me a final report of what was fixed, what remains, and any risks.
- Commit: "test: hardening and pilot readiness".
```

---

## Prompt 6: Release Build and CI

```
Follow docs/AGENT_RULES.md. GOAL: a signed release build and a repeatable pipeline.

1. App identity: app name "Tzion Stockly", launcher icon and splash screen using the navy #1F3864 and teal #14B8A6 branding (generate with flutter_launcher_icons and flutter_native_splash; I will provide the logo file in assets/branding/).
2. Android release: set the application id com.tzion.tzion_stockly, versioning, minimum SDK suitable for low-end phones, ProGuard/R8 settings that do not break Drift or Supabase, and release signing using a keystore that is NOT committed to Git. Explain how I create and back up the keystore safely.
3. Build commands for a release APK and an app bundle, with --dart-define for SUPABASE_URL and SUPABASE_ANON_KEY. Document them in the README.
4. CI with GitHub Actions: on each push run flutter analyze and flutter test; on version tags build the release artifacts (using repository secrets for keystore and keys).
5. Play Store preparation checklist: privacy policy outline (what data is collected: account email, business data), data safety form answers, store listing text in English and Swahili, screenshots list, content rating notes. State clearly that the app has no in-app purchases and no ads.
6. Keep-alive and backups: verify the keep-alive workflow runs, and write a short "operations" doc: how to check Supabase health, how to export backups, and the plan to move to the Supabase Pro tier before onboarding paying clients.

VERIFY
- Release APK installs and runs on my device; give me file sizes and the steps you ran.
- Commit and tag: "v0.1.0".
```

---

## Utility Prompts

### Debug prompt
```
Follow docs/AGENT_RULES.md. Something is broken.
WHAT I DID: <steps>
WHAT I EXPECTED: <expected>
WHAT HAPPENED: <actual>
ERROR / LOGS: <paste exact error text>
Find the root cause first and explain it in plain words. Then fix it with the smallest safe change, add a test that would have caught it, run analyze and tests, and tell me what you changed.
```

### Review prompt (before each Git commit)
```
Follow docs/AGENT_RULES.md. Review all uncommitted changes. List any rule violations, unrequested packages or features, missing tests, hard-coded strings, and risky code. Do not change anything yet; give me the list and your recommendations.
```

### New feature prompt template
```
Follow docs/AGENT_RULES.md. I want to add: <feature>.
First, write a short plan covering: screens, database changes (with migration), sync impact, permissions by role, and tests. Wait for my approval before coding.
```

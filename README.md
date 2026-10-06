# Tzion Stockly

An offline-first inventory management and analysis application for small shops in Tanzania.

## Features
- **Offline First:** Reads and writes directly to local Drift (SQLite) database.
- **Stock Ledger:** Append-only inventory movements tracking.
- **Localization:** Full support for English (`en`) and Swahili (`sw`).
- **Responsive Layout:** Mobile bottom navigation bar and desktop/tablet navigation rail.
- **Material 3 Design:** Deep Navy (`#1F3864`) & Teal (`#14B8A6`) theme.

## Architecture
- `lib/app/`: Navigation router, Material 3 themes, responsive shell layout.
- `lib/core/`: Local database, sync engine, network utilities, common UI widgets.
- `lib/features/`: Feature-first modules (`auth`, `products`, `stock`, `partners`, `sales`, `dashboard`, `reports`, `settings`).
- `lib/l10n/`: ARB localization files.

## Documentation
Refer to `docs/AGENT_RULES.md` for project guidelines, engineering rules, and implementation phases.

## Getting Started

### Prerequisites
- Flutter SDK (>= 3.10.0)
- Dart SDK (>= 3.0.0)

### Setup & Run
```bash
flutter pub get
flutter gen-l10n
flutter run
```

### Running Tests & Linter
```bash
flutter test
flutter analyze
```

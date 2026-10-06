import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/database/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final exportService = ref.watch(exportServiceProvider);
    final bizId = ref.watch(currentBusinessIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n?.navMore ?? 'More'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.people_outline, color: Color(0xFF1F3864)),
            title: const Text('Suppliers & Customers (Partners)'),
            subtitle: const Text('Manage supplier contacts & customer records'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              context.push('/partners');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.download_for_offline, color: Color(0xFF14B8A6)),
            title: const Text('Backup Export (All Data as CSV)'),
            subtitle: const Text('Export all products, partners, and inventory history'),
            trailing: const Icon(Icons.file_upload_outlined),
            onTap: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Generating full backup CSV...')),
              );
              await exportService.exportFullBackupCsv(bizId);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.language, color: Color(0xFF1F3864)),
            title: const Text('Language / Lugha'),
            subtitle: const Text('English / Kiswahili'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.palette_outlined, color: Color(0xFF14B8A6)),
            title: const Text('Theme'),
            subtitle: const Text('Light / Dark Mode'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.sync_rounded, color: Colors.blue),
            title: const Text('Sync & Backup'),
            subtitle: const Text('Local storage & cloud synchronization'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.grey),
            title: const Text('About Tzion Stockly'),
            subtitle: const Text('v0.1.0 (Phase 2 Analytics & Export)'),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

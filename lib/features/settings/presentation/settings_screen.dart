import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../l10n/app_localizations.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
            subtitle: const Text('v0.1.0 (Phase 1 Local Core)'),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

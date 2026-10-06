import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import '../../../app/theme.dart';
import '../../../core/database/providers.dart';
import '../../auth/domain/role_permissions.dart';
import '../domain/settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _toggleAppLock(BuildContext context, WidgetRef ref, bool enable) async {
    if (enable) {
      final auth = LocalAuthentication();
      try {
        final canCheck = await auth.canCheckBiometrics || await auth.isDeviceSupported();
        if (canCheck) {
          final authenticated = await auth.authenticate(
            localizedReason: 'Authenticate to enable App Lock',
            biometricOnly: false,
          );
          if (authenticated) {
            ref.read(appLockEnabledProvider.notifier).state = true;
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('App Lock enabled successfully.')),
              );
            }
          }
          return;
        }
      } catch (_) {}
    }
    ref.read(appLockEnabledProvider.notifier).state = enable;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exportService = ref.watch(exportServiceProvider);
    final bizId = ref.watch(currentBusinessIdProvider);

    final currentLocale = ref.watch(localeProvider);
    final currentThemeMode = ref.watch(themeModeProvider);
    final negativeStockRule = ref.watch(negativeStockBehaviorProvider);
    final slowMoverDays = ref.watch(slowMoverDaysProvider);
    final appLockEnabled = ref.watch(appLockEnabledProvider);

    final authState = ref.watch(authNotifierProvider);
    final userRole = ref.watch(userRoleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Shop Info'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // Account / Profile Card
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppTheme.primaryNavy,
                    child: Icon(
                      authState.isAuthenticated ? Icons.store_rounded : Icons.wifi_off_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          authState.isAuthenticated
                              ? authState.userProfile?.email ?? 'Logged In'
                              : 'Offline Guest Mode',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: userRole == UserRole.owner
                                    ? AppTheme.primaryNavy.withValues(alpha: 0.15)
                                    : AppTheme.secondaryTeal.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                userRole.toFormattedString(),
                                style: TextStyle(
                                  color: userRole == UserRole.owner ? AppTheme.primaryNavy : AppTheme.secondaryTeal,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'ID: ${bizId.substring(0, 8)}...',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      if (authState.isAuthenticated) {
                        ref.read(authNotifierProvider.notifier).signOut();
                      } else {
                        context.push('/login');
                      }
                    },
                    child: Text(authState.isAuthenticated ? 'Sign Out' : 'Sign In'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),
          const _SectionHeader(title: 'BUSINESS & MANAGEMENT'),

          ListTile(
            leading: const Icon(Icons.people_alt_outlined, color: AppTheme.primaryNavy),
            title: const Text('Partners (Suppliers & Customers)'),
            subtitle: const Text('Manage supplier contacts & customer directory'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/partners'),
          ),

          ListTile(
            leading: const Icon(Icons.group_add_outlined, color: AppTheme.primaryNavy),
            title: const Text('Shop Team & Roles'),
            subtitle: Text(
              RolePermissions.canManageUsers(userRole)
                  ? 'Invite team members & set permissions'
                  : 'View shop team members (Owner only to edit)',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/team'),
          ),

          const Divider(),
          const _SectionHeader(title: 'PREFERENCES & LOCALIZATION'),

          ListTile(
            leading: const Icon(Icons.language, color: AppTheme.secondaryTeal),
            title: const Text('Language / Lugha'),
            subtitle: Text(currentLocale.languageCode == 'sw' ? 'Kiswahili' : 'English'),
            trailing: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'en', label: Text('EN')),
                ButtonSegment(value: 'sw', label: Text('SW')),
              ],
              selected: {currentLocale.languageCode},
              onSelectionChanged: (selection) {
                ref.read(localeProvider.notifier).state = Locale(selection.first);
              },
            ),
          ),

          ListTile(
            leading: const Icon(Icons.palette_outlined, color: AppTheme.secondaryTeal),
            title: const Text('App Theme'),
            subtitle: Text(currentThemeMode == ThemeMode.dark
                ? 'Dark Mode'
                : currentThemeMode == ThemeMode.light
                    ? 'Light Mode'
                    : 'System Default'),
            trailing: DropdownButton<ThemeMode>(
              value: currentThemeMode,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              ],
              onChanged: (mode) {
                if (mode != null) {
                  ref.read(themeModeProvider.notifier).state = mode;
                }
              },
            ),
          ),

          const Divider(),
          const _SectionHeader(title: 'INVENTORY & RULES'),

          ListTile(
            leading: const Icon(Icons.warning_amber_rounded, color: AppTheme.warningAmber),
            title: const Text('Negative Stock Handling'),
            subtitle: Text(negativeStockRule == 'block'
                ? 'Block sales when stock is insufficient'
                : 'Warn operator but allow sale'),
            trailing: Switch(
              value: negativeStockRule == 'block',
              onChanged: (isBlock) {
                ref.read(negativeStockBehaviorProvider.notifier).state = isBlock ? 'block' : 'warn';
              },
            ),
          ),

          ListTile(
            leading: const Icon(Icons.timer_outlined, color: AppTheme.warningAmber),
            title: const Text('Slow Mover Threshold'),
            subtitle: Text('Flag items with no sales in $slowMoverDays days'),
            trailing: DropdownButton<int>(
              value: slowMoverDays,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 15, child: Text('15 Days')),
                DropdownMenuItem(value: 30, child: Text('30 Days')),
                DropdownMenuItem(value: 60, child: Text('60 Days')),
              ],
              onChanged: (days) {
                if (days != null) {
                  ref.read(slowMoverDaysProvider.notifier).state = days;
                }
              },
            ),
          ),

          ListTile(
            leading: const Icon(Icons.lock_person_outlined, color: AppTheme.primaryNavy),
            title: const Text('Security App Lock'),
            subtitle: const Text('Require PIN or biometrics to open app'),
            trailing: Switch(
              value: appLockEnabled,
              onChanged: (val) => _toggleAppLock(context, ref, val),
            ),
          ),

          const Divider(),
          const _SectionHeader(title: 'BACKUP & EXPORT'),

          ListTile(
            leading: const Icon(Icons.download_for_offline, color: AppTheme.successGreen),
            title: const Text('Full Backup Export (CSV)'),
            subtitle: const Text('Export all products, partners, and ledger history'),
            trailing: const Icon(Icons.file_upload_outlined),
            onTap: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Generating full backup CSV...')),
              );
              await exportService.exportFullBackupCsv(bizId);
            },
          ),

          const Divider(),
          const _SectionHeader(title: 'ABOUT'),

          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.grey),
            title: const Text('Tzion Stockly'),
            subtitle: const Text('v0.1.0 • Offline-First Inventory Management for Tanzania'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

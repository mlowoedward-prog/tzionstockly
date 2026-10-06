import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme.dart';
import '../database/providers.dart';

enum SyncState { synced, syncing, offline, pending }

class SyncStatusChip extends StatelessWidget {
  final SyncState state;
  final int pendingCount;
  final VoidCallback? onTap;

  const SyncStatusChip({
    super.key,
    this.state = SyncState.synced,
    this.pendingCount = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color chipColor;
    Color textColor;
    IconData icon;
    String label;

    switch (state) {
      case SyncState.synced:
        chipColor = AppTheme.successGreen.withValues(alpha: 0.15);
        textColor = AppTheme.successGreen;
        icon = Icons.check_circle_outline;
        label = 'Synced';
        break;
      case SyncState.syncing:
        chipColor = AppTheme.secondaryTeal.withValues(alpha: 0.15);
        textColor = AppTheme.secondaryTeal;
        icon = Icons.sync;
        label = 'Syncing...';
        break;
      case SyncState.offline:
        chipColor = Colors.grey.withValues(alpha: 0.2);
        textColor = Colors.grey.shade700;
        icon = Icons.cloud_off;
        label = 'Offline';
        break;
      case SyncState.pending:
        chipColor = AppTheme.warningAmber.withValues(alpha: 0.15);
        textColor = AppTheme.warningAmber;
        icon = Icons.pending_actions;
        label = 'Pending ($pendingCount)';
        break;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: chipColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: textColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state == SyncState.syncing)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(textColor),
                ),
              )
            else
              Icon(icon, size: 14, color: textColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReactiveSyncStatusChip extends ConsumerWidget {
  const ReactiveSyncStatusChip({super.key});

  void _showSyncModal(BuildContext context, WidgetRef ref) {
    final statusInfo = ref.read(syncStatusProvider);
    final authState = ref.read(authNotifierProvider);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.cloud_sync_rounded,
                    color: AppTheme.primaryNavy,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Cloud Sync Status',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  authState.isAuthenticated ? Icons.account_circle : Icons.person_outline,
                  color: AppTheme.primaryNavy,
                ),
                title: Text(
                  authState.isAuthenticated
                      ? authState.userProfile?.email ?? 'Logged In'
                      : 'Offline Guest Mode',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  authState.isAuthenticated
                      ? 'Business ID: ${authState.userProfile?.businessId.substring(0, 8)}...'
                      : 'Local data will sync when you register or sign in',
                ),
                trailing: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    if (authState.isAuthenticated) {
                      ref.read(authNotifierProvider.notifier).signOut();
                    } else {
                      context.push('/login');
                    }
                  },
                  child: Text(authState.isAuthenticated ? 'Sign Out' : 'Sign In'),
                ),
              ),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Pending Changes:'),
                  Text(
                    '${statusInfo.pendingCount} records',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Last Synced:'),
                  Text(
                    statusInfo.lastSyncedAt != null
                        ? '${statusInfo.lastSyncedAt!.hour}:${statusInfo.lastSyncedAt!.minute.toString().padLeft(2, '0')}'
                        : 'Never',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  final bizId = ref.read(currentBusinessIdProvider);
                  ref.read(syncEngineProvider).triggerSync(businessId: bizId);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.sync),
                label: const Text('Sync Now'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: AppTheme.primaryNavy,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chipState = ref.watch(chipSyncStateProvider);
    final statusInfo = ref.watch(syncStatusProvider);

    return SyncStatusChip(
      state: chipState,
      pendingCount: statusInfo.pendingCount,
      onTap: () => _showSyncModal(context, ref),
    );
  }
}

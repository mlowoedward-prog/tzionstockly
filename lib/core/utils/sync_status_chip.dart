import 'package:flutter/material.dart';
import '../../app/theme.dart';

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

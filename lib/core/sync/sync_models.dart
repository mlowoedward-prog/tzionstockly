enum RealSyncState { synced, syncing, offline, pending, error }

class SyncStatusInfo {
  final RealSyncState state;
  final int pendingCount;
  final DateTime? lastSyncedAt;
  final String? lastErrorMessage;

  const SyncStatusInfo({
    required this.state,
    this.pendingCount = 0,
    this.lastSyncedAt,
    this.lastErrorMessage,
  });
}

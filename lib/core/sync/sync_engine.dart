import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../database/database_service.dart';
import '../network/supabase_config.dart';
import 'sync_models.dart';
import 'sync_push.dart';
import 'sync_pull.dart';

class SyncEngine extends ChangeNotifier {
  final DatabaseService dbService;
  late final SyncPushEngine pushEngine;
  late final SyncPullEngine pullEngine;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _debounceTimer;
  bool _isSyncing = false;

  SyncStatusInfo _status = const SyncStatusInfo(state: RealSyncState.synced);
  SyncStatusInfo get status => _status;

  SyncEngine({required this.dbService}) {
    final client = SupabaseConfig.client;
    pushEngine = SyncPushEngine(dbService: dbService, supabaseClient: client);
    pullEngine = SyncPullEngine(dbService: dbService, supabaseClient: client);

    _initConnectivityListener();
  }

  void _initConnectivityListener() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        triggerSync(businessId: DatabaseService.defaultBusinessId);
      } else {
        _setStatus(RealSyncState.offline);
      }
    });
  }

  void scheduleDebouncedSync({required String businessId}) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1500), () {
      triggerSync(businessId: businessId);
    });
  }

  Future<void> triggerSync({required String businessId}) async {
    if (_isSyncing) return;

    final pendingCount = await dbService.getSyncQueueCount();

    if (!SupabaseConfig.isConfigured) {
      _setStatus(RealSyncState.offline, pendingCount: pendingCount);
      return;
    }

    _isSyncing = true;
    _setStatus(RealSyncState.syncing, pendingCount: pendingCount);

    try {
      // 1. Push local changes
      await pushEngine.pushPendingChanges();

      // 2. Pull remote changes
      await pullEngine.pullRemoteChanges(businessId);

      final newPending = await dbService.getSyncQueueCount();
      _setStatus(
        newPending > 0 ? RealSyncState.pending : RealSyncState.synced,
        pendingCount: newPending,
        lastSyncedAt: DateTime.now(),
      );
    } catch (e) {
      final newPending = await dbService.getSyncQueueCount();
      _setStatus(
        RealSyncState.error,
        pendingCount: newPending,
        lastErrorMessage: e.toString(),
      );
    } finally {
      _isSyncing = false;
    }
  }

  void _setStatus(
    RealSyncState state, {
    int pendingCount = 0,
    DateTime? lastSyncedAt,
    String? lastErrorMessage,
  }) {
    _status = SyncStatusInfo(
      state: state,
      pendingCount: pendingCount,
      lastSyncedAt: lastSyncedAt ?? _status.lastSyncedAt,
      lastErrorMessage: lastErrorMessage,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }
}

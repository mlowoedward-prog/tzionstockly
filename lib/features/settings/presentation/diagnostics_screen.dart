import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../app/theme.dart';
import '../../../core/database/providers.dart';
import '../../../core/utils/diagnostics_logger.dart';

class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = DiagnosticsLogger.getLogs();
    final syncStatus = ref.watch(syncStatusProvider);
    final dateFormat = DateFormat('HH:mm:ss');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics & Sync Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear Logs',
            onPressed: () {
              DiagnosticsLogger.clear();
              (context as Element).markNeedsBuild();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Metrics Card Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: AppTheme.primaryNavy.withValues(alpha: 0.05),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _MetricTile(
                  label: 'Sync State',
                  value: syncStatus.state.name.toUpperCase(),
                  color: AppTheme.primaryNavy,
                ),
                _MetricTile(
                  label: 'Pending Queue',
                  value: '${syncStatus.pendingCount}',
                  color: AppTheme.warningAmber,
                ),
                _MetricTile(
                  label: 'Total Logs',
                  value: '${logs.length}',
                  color: AppTheme.secondaryTeal,
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Log List
          Expanded(
            child: logs.isEmpty
                ? const Center(
                    child: Text(
                      'No diagnostic logs recorded yet.\nSync events and system status will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: logs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = logs[index];
                      final isError = item.level == 'ERROR';
                      final isWarn = item.level == 'WARN';

                      return Card(
                        child: ListTile(
                          leading: Icon(
                            isError
                                ? Icons.error_outline
                                : isWarn
                                    ? Icons.warning_amber
                                    : Icons.info_outline,
                            color: isError
                                ? AppTheme.errorRed
                                : isWarn
                                    ? AppTheme.warningAmber
                                    : AppTheme.secondaryTeal,
                          ),
                          title: Text(
                            '[${item.category.toUpperCase()}] ${item.message}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            dateFormat.format(item.timestamp),
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

class DiagnosticLogEntry {
  final DateTime timestamp;
  final String category; // 'sync', 'network', 'db', 'auth'
  final String message;
  final String level; // 'INFO', 'WARN', 'ERROR'

  const DiagnosticLogEntry({
    required this.timestamp,
    required this.category,
    required this.message,
    this.level = 'INFO',
  });
}

class DiagnosticsLogger {
  static final List<DiagnosticLogEntry> _logs = [];
  static const int _maxLogs = 100;

  static void log(String category, String message, {String level = 'INFO'}) {
    // Sanitize message to strip potential tokens or secret keys
    final sanitizedMessage = message
        .replaceAll(RegExp(r'eyJ[A-Za-z0-9-_=]+\.[A-Za-z0-9-_=]+\.?[A-Za-z0-9-_.+/=]*'), '[TOKEN_REDACTED]')
        .replaceAll(RegExp(r'apikey=[^&]+'), 'apikey=[REDACTED]');

    _logs.insert(
      0,
      DiagnosticLogEntry(
        timestamp: DateTime.now(),
        category: category,
        message: sanitizedMessage,
        level: level,
      ),
    );

    if (_logs.length > _maxLogs) {
      _logs.removeLast();
    }
  }

  static List<DiagnosticLogEntry> getLogs() => List.unmodifiable(_logs);

  static void clear() => _logs.clear();
}

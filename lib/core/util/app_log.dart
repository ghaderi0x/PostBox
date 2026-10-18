import 'redact.dart';

enum LogLevel { info, warn, error }

class LogEntry {
  const LogEntry(this.time, this.level, this.message);
  final DateTime time;
  final LogLevel level;
  final String message;
}

/// Small in-memory ring buffer. Messages are scrubbed before storing, so the
/// export can be shared without leaking tokens or query strings.
class AppLog {
  AppLog({this.capacity = 300});

  final int capacity;
  final List<LogEntry> _entries = <LogEntry>[];

  List<LogEntry> get entries => List<LogEntry>.unmodifiable(_entries);

  void log(LogLevel level, String message) {
    _entries.add(LogEntry(DateTime.now(), level, Redactor.freeText(message)));
    if (_entries.length > capacity) {
      _entries.removeRange(0, _entries.length - capacity);
    }
  }

  void info(String m) => log(LogLevel.info, m);
  void warn(String m) => log(LogLevel.warn, m);
  void error(String m) => log(LogLevel.error, m);

  void clear() => _entries.clear();

  String export() {
    final b = StringBuffer();
    for (final e in _entries) {
      b.writeln('${e.time.toIso8601String()} ${e.level.name.toUpperCase()} ${e.message}');
    }
    return b.toString();
  }
}

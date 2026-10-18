class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.ts,
    required this.method,
    required this.url,
    this.status,
    this.durationMs,
    this.size,
    this.error,
    this.requestJson,
  });

  final String id;

  /// Epoch milliseconds.
  final int ts;
  final String method;
  final String url;
  final int? status;
  final int? durationMs;
  final int? size;
  final String? error;

  /// Full request definition for replay. Null when sensitive details were
  /// omitted by the user's privacy setting.
  final String? requestJson;
}

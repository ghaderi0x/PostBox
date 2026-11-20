import '../domain/http_engine.dart';

/// Response of one request/response exchange before redirects are handled.
class RawExchange {
  RawExchange({
    required this.status,
    required this.reason,
    required this.headers,
    required this.body,
    required this.protocol,
    required this.connect,
    required this.wait,
    required this.close,
    this.tls,
  });

  final int status;
  final String reason;
  final Map<String, List<String>> headers;
  final Stream<List<int>> body;
  final String protocol;
  final Duration connect;
  final Duration wait;
  final TlsInfo? tls;

  /// Releases the connection. Safe to call more than once.
  final Future<void> Function() close;

  String? header(String name) {
    final lower = name.toLowerCase();
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == lower) {
        return e.value.isEmpty ? null : e.value.first;
      }
    }
    return null;
  }
}

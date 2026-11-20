import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../http/data/io_http_engine.dart';
import '../http/domain/http_engine.dart';

enum StreamEventType { open, message, event, sent, close, error }

class StreamEvent {
  StreamEvent(this.type, this.data, {this.label = '', DateTime? time})
    : time = time ?? DateTime.now();

  final StreamEventType type;
  final String data;

  /// SSE event name or similar short label.
  final String label;
  final DateTime time;
}

abstract interface class StreamSession {
  Stream<StreamEvent> get events;
  Future<void> send(String data);
  Future<void> close();
}

/// Parses SSE text lines into events. Public for testing.
Stream<StreamEvent> parseSse(Stream<String> lines) async* {
  var event = '';
  final data = <String>[];
  await for (final line in lines) {
    if (line.isEmpty) {
      if (data.isNotEmpty) {
        yield StreamEvent(
          StreamEventType.event,
          data.join('\n'),
          label: event.isEmpty ? 'message' : event,
        );
      }
      event = '';
      data.clear();
      continue;
    }
    if (line.startsWith(':')) continue;
    final idx = line.indexOf(':');
    final field = idx < 0 ? line : line.substring(0, idx);
    var value = idx < 0 ? '' : line.substring(idx + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    if (field == 'event') {
      event = value;
    } else if (field == 'data') {
      data.add(value);
    }
  }
  if (data.isNotEmpty) {
    yield StreamEvent(
      StreamEventType.event,
      data.join('\n'),
      label: event.isEmpty ? 'message' : event,
    );
  }
}

class SseSession implements StreamSession {
  SseSession._(this._client, this._controller);

  final HttpClient _client;
  final StreamController<StreamEvent> _controller;

  static Future<SseSession> connect(HttpRequestSpec spec) async {
    final client = createConfiguredClient(spec);
    final controller = StreamController<StreamEvent>();
    final session = SseSession._(client, controller);
    unawaited(session._run(spec));
    return session;
  }

  Future<void> _run(HttpRequestSpec spec) async {
    try {
      final req = await _client.openUrl(spec.method, spec.url);
      req.followRedirects = false;
      req.headers.set('Accept', 'text/event-stream');
      spec.headers.forEach(
        (k, v) => req.headers.set(k, v, preserveHeaderCase: true),
      );
      final res = await req.close();
      if (res.statusCode != 200) {
        _controller.add(
          StreamEvent(StreamEventType.error, 'HTTP ${res.statusCode}'),
        );
        await close();
        return;
      }
      _controller.add(StreamEvent(StreamEventType.open, 'HTTP 200'));
      final lines = utf8.decoder.bind(res).transform(const LineSplitter());
      await for (final e in parseSse(lines)) {
        if (_controller.isClosed) return;
        _controller.add(e);
      }
      if (!_controller.isClosed) {
        _controller.add(StreamEvent(StreamEventType.close, ''));
      }
    } on SocketException catch (e) {
      if (!_controller.isClosed) {
        _controller.add(StreamEvent(StreamEventType.error, e.message));
      }
    } on HttpException catch (e) {
      if (!_controller.isClosed) {
        _controller.add(StreamEvent(StreamEventType.error, e.message));
      }
    } on TlsException catch (e) {
      if (!_controller.isClosed) {
        _controller.add(StreamEvent(StreamEventType.error, e.message));
      }
    } finally {
      await close();
    }
  }

  @override
  Stream<StreamEvent> get events => _controller.stream;

  @override
  Future<void> send(String data) async {}

  @override
  Future<void> close() async {
    _client.close(force: true);
    if (!_controller.isClosed) await _controller.close();
  }
}

class WebSocketSession implements StreamSession {
  WebSocketSession._(this._socket, this._controller) {
    _socket.listen(
      (dynamic m) {
        if (m is String) {
          _controller.add(StreamEvent(StreamEventType.message, m));
        } else if (m is List<int>) {
          _controller.add(
            StreamEvent(StreamEventType.message, '[binary ${m.length} bytes]'),
          );
        }
      },
      onError: (Object e) =>
          _controller.add(StreamEvent(StreamEventType.error, '$e')),
      onDone: () {
        if (!_controller.isClosed) {
          _controller.add(
            StreamEvent(StreamEventType.close, '${_socket.closeCode ?? ''}'),
          );
          _controller.close();
        }
      },
    );
  }

  final WebSocket _socket;
  final StreamController<StreamEvent> _controller;

  /// Accepts ws/wss, and maps http/https to them.
  static Uri toWebSocketUri(Uri u) {
    if (u.scheme == 'ws' || u.scheme == 'wss') return u;
    return u.replace(scheme: u.scheme == 'https' ? 'wss' : 'ws');
  }

  static Future<WebSocketSession> connect(HttpRequestSpec spec) async {
    final client = createConfiguredClient(spec);
    final socket = await WebSocket.connect(
      toWebSocketUri(spec.url).toString(),
      headers: spec.headers,
      customClient: client,
    ).timeout(spec.timeout);
    final controller = StreamController<StreamEvent>();
    controller.add(StreamEvent(StreamEventType.open, ''));
    return WebSocketSession._(socket, controller);
  }

  @override
  Stream<StreamEvent> get events => _controller.stream;

  @override
  Future<void> send(String data) async {
    _socket.add(data);
    if (!_controller.isClosed) {
      _controller.add(StreamEvent(StreamEventType.sent, data));
    }
  }

  @override
  Future<void> close() async {
    await _socket.close();
  }
}

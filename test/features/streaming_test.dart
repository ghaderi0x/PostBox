import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/features/http/domain/http_engine.dart';
import 'package:postbox/features/streaming/stream_service.dart';

void main() {
  test('parseSse handles events, multi-line data, comments and ids', () async {
    final lines = Stream<String>.fromIterable(<String>[
      ': comment',
      'data: one',
      '',
      'event: update',
      'data: line1',
      'data: line2',
      'id: 5',
      '',
      'data:nospace',
      '',
      'data: tail-without-blank-line',
    ]);
    final events = await parseSse(lines).toList();
    expect(events.map((e) => (e.label, e.data)).toList(), <(String, String)>[
      ('message', 'one'),
      ('update', 'line1\nline2'),
      ('message', 'nospace'),
      ('message', 'tail-without-blank-line'),
    ]);
  });

  test('SseSession receives events from a real server', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      req.response.headers.contentType = ContentType('text', 'event-stream');
      req.response.write('data: hello\n\n');
      await req.response.flush();
      req.response.write('event: tick\ndata: 1\n\n');
      await req.response.close();
    });
    final session = await SseSession.connect(
      HttpRequestSpec(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:${server.port}/'),
      ),
    );
    final events = await session.events.toList().timeout(
      const Duration(seconds: 5),
    );
    final data = events
        .where((e) => e.type == StreamEventType.event)
        .map((e) => e.data)
        .toList();
    expect(data, <String>['hello', '1']);
    expect(events.first.type, StreamEventType.open);
  });

  test('SseSession reports non-200 responses', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      req.response.statusCode = 503;
      await req.response.close();
    });
    final session = await SseSession.connect(
      HttpRequestSpec(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:${server.port}/'),
      ),
    );
    final events = await session.events.toList().timeout(
      const Duration(seconds: 5),
    );
    expect(events.single.type, StreamEventType.error);
    expect(events.single.data, contains('503'));
  });

  test('WebSocketSession echoes messages', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      ws.listen((m) => ws.add('echo:$m'), onDone: () => ws.close());
    });
    final session = await WebSocketSession.connect(
      HttpRequestSpec(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:${server.port}/'),
      ),
    );
    final received = <StreamEvent>[];
    final done = Completer<void>();
    final sub = session.events.listen((e) {
      received.add(e);
      if (e.type == StreamEventType.message) done.complete();
    });
    await session.send('hi');
    await done.future.timeout(const Duration(seconds: 5));
    await session.close();
    await sub.cancel();
    expect(
      received.any((e) => e.type == StreamEventType.sent && e.data == 'hi'),
      isTrue,
    );
    expect(
      received.any(
        (e) => e.type == StreamEventType.message && e.data == 'echo:hi',
      ),
      isTrue,
    );
  });

  test('toWebSocketUri maps http schemes', () {
    expect(
      WebSocketSession.toWebSocketUri(Uri.parse('http://a/x')).scheme,
      'ws',
    );
    expect(
      WebSocketSession.toWebSocketUri(Uri.parse('https://a/x')).scheme,
      'wss',
    );
    expect(
      WebSocketSession.toWebSocketUri(Uri.parse('wss://a/x')).scheme,
      'wss',
    );
  });
}

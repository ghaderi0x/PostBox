import 'dart:convert';
import 'dart:typed_data';

import 'package:postbox/features/http/domain/http_engine.dart';

HttpResult fakeResult({
  int status = 200,
  String reason = 'OK',
  Map<String, List<String>> headers = const <String, List<String>>{},
  String body = '',
  Duration duration = const Duration(milliseconds: 120),
}) => HttpResult(
  statusCode: status,
  reasonPhrase: reason,
  headers: headers,
  body: Uint8List.fromList(utf8.encode(body)),
  truncated: false,
  duration: duration,
  finalUrl: Uri.parse('https://example.test/'),
  redirects: const <Uri>[],
);

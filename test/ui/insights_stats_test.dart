import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/features/history/domain/history_models.dart';
import 'package:postbox/ui/insights/insights_page.dart';

HistoryEntry _e(int i, String method, int? status, int? ms, {String? error}) =>
    HistoryEntry(
      id: '$i',
      ts: 1000 + i,
      method: method,
      url: 'https://api.example.com/users/$i',
      status: status,
      durationMs: ms,
      error: error,
    );

void main() {
  test('counts outcomes and method totals', () {
    final st = HistoryStats(<HistoryEntry>[
      _e(1, 'GET', 200, 100),
      _e(2, 'GET', 301, 200),
      _e(3, 'POST', 404, 300),
      _e(4, 'POST', 500, 400),
      _e(5, 'GET', null, null, error: 'timeout'),
    ]);
    expect(st.total, 5);
    expect(st.s2xx, 1);
    expect(st.s3xx, 1);
    expect(st.s4xx, 1);
    expect(st.s5xx, 1);
    expect(st.failed, 1);
    expect(st.methods['GET'], 3);
    expect(st.methods['POST'], 2);
    expect(st.successRate, closeTo(0.4, 1e-9));
  });

  test('average and p95 ignore entries without a time', () {
    final st = HistoryStats(<HistoryEntry>[
      for (var i = 1; i <= 20; i++) _e(i, 'GET', 200, i * 10),
      _e(99, 'GET', null, null, error: 'x'),
    ]);
    expect(st.averageMs, closeTo(105, 1e-9));
    expect(st.p95Ms, 190);
  });

  test('latency series is oldest to newest and capped at 60', () {
    final st = HistoryStats(<HistoryEntry>[
      for (var i = 1; i <= 80; i++) _e(i, 'GET', 200, i),
    ]);
    expect(st.latest, hasLength(60));
    expect(st.latest.first, 21);
    expect(st.latest.last, 80);
  });

  test('slowest endpoints are ranked by average time', () {
    final st = HistoryStats(<HistoryEntry>[
      HistoryEntry(
        id: 'a',
        ts: 1,
        method: 'GET',
        url: 'https://x.io/slow',
        status: 200,
        durationMs: 900,
      ),
      HistoryEntry(
        id: 'b',
        ts: 2,
        method: 'GET',
        url: 'https://x.io/fast',
        status: 200,
        durationMs: 50,
      ),
    ]);
    expect(st.slowest().first.key, 'x.io/slow');
  });

  test('empty history does not divide by zero', () {
    final st = HistoryStats(const <HistoryEntry>[]);
    expect(st.total, 0);
    expect(st.successRate, 0);
    expect(st.averageMs, 0);
    expect(st.p95Ms, 0);
  });
}

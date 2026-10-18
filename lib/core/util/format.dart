import 'jalali.dart';

/// Number, size, duration and date formatting honouring the user's digit and
/// calendar settings. Latin digits and Gregorian dates are the default.
class Fmt {
  const Fmt({this.persianDigits = false, this.jalali = false});

  final bool persianDigits;
  final bool jalali;

  static const String _fa = '۰۱۲۳۴۵۶۷۸۹';

  String digits(String s) {
    if (!persianDigits) return s;
    return s.replaceAllMapped(
      RegExp('[0-9]'),
      (m) => _fa[int.parse(m[0]!)],
    );
  }

  String integer(int n) => digits('$n');

  String bytes(int n) {
    if (n < 1024) return digits('$n B');
    if (n < 1024 * 1024) return digits('${(n / 1024).toStringAsFixed(1)} KB');
    if (n < 1024 * 1024 * 1024) {
      return digits('${(n / (1024 * 1024)).toStringAsFixed(2)} MB');
    }
    return digits('${(n / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB');
  }

  String duration(Duration d) {
    final ms = d.inMilliseconds;
    if (ms < 1000) return digits('$ms ms');
    return digits('${(ms / 1000).toStringAsFixed(2)} s');
  }

  String dateTime(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final y = jalali ? gregorianToJalali(l.year, l.month, l.day) : <int>[l.year, l.month, l.day];
    return digits('${y[0]}/${two(y[1])}/${two(y[2])} ${two(l.hour)}:${two(l.minute)}');
  }
}

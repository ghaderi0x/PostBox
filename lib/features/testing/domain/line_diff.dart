import 'dart:typed_data';

enum DiffOp { same, added, removed }

class DiffLine {
  const DiffLine(this.op, this.text);
  final DiffOp op;
  final String text;
}

/// Line-based diff using a longest-common-subsequence table. Returns null when
/// the changed region is too large to compare (memory is bounded by
/// [maxCells] table cells).
List<DiffLine>? lineDiff(List<String> a, List<String> b, {int maxCells = 4000000}) {
  var start = 0;
  while (start < a.length && start < b.length && a[start] == b[start]) {
    start++;
  }
  var endA = a.length;
  var endB = b.length;
  while (endA > start && endB > start && a[endA - 1] == b[endB - 1]) {
    endA--;
    endB--;
  }
  final ma = endA - start;
  final mb = endB - start;
  if (ma * mb > maxCells) return null;

  final out = <DiffLine>[
    for (var i = 0; i < start; i++) DiffLine(DiffOp.same, a[i]),
  ];

  final dp = List<Int32List>.generate(ma + 1, (_) => Int32List(mb + 1));
  for (var i = ma - 1; i >= 0; i--) {
    for (var j = mb - 1; j >= 0; j--) {
      if (a[start + i] == b[start + j]) {
        dp[i][j] = dp[i + 1][j + 1] + 1;
      } else {
        final down = dp[i + 1][j];
        final right = dp[i][j + 1];
        dp[i][j] = down >= right ? down : right;
      }
    }
  }
  var i = 0;
  var j = 0;
  while (i < ma && j < mb) {
    if (a[start + i] == b[start + j]) {
      out.add(DiffLine(DiffOp.same, a[start + i]));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      out.add(DiffLine(DiffOp.removed, a[start + i]));
      i++;
    } else {
      out.add(DiffLine(DiffOp.added, b[start + j]));
      j++;
    }
  }
  while (i < ma) {
    out.add(DiffLine(DiffOp.removed, a[start + i]));
    i++;
  }
  while (j < mb) {
    out.add(DiffLine(DiffOp.added, b[start + j]));
    j++;
  }
  for (var k = endA; k < a.length; k++) {
    out.add(DiffLine(DiffOp.same, a[k]));
  }
  return out;
}

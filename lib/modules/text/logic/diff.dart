import 'package:flutter/foundation.dart';

enum DiffOp { equal, insert, delete }

@immutable
class DiffEdit<T> {
  const DiffEdit(this.op, this.item);
  final DiffOp op;
  final T item;

  @override
  String toString() => '${op.name}($item)';
}

/// Myers O((N+M)·D) shortest edit script between two sequences.
List<DiffEdit<T>> myersDiff<T>(List<T> a, List<T> b, {bool Function(T, T)? equals}) {
  final eq = equals ?? (T x, T y) => x == y;
  // Trim common prefix/suffix — cheap and makes typical edits near-linear.
  var start = 0;
  while (start < a.length && start < b.length && eq(a[start], b[start])) {
    start++;
  }
  var endA = a.length, endB = b.length;
  while (endA > start && endB > start && eq(a[endA - 1], b[endB - 1])) {
    endA--;
    endB--;
  }
  final prefix = [for (var i = 0; i < start; i++) DiffEdit(DiffOp.equal, a[i])];
  final suffix = [for (var i = endA; i < a.length; i++) DiffEdit(DiffOp.equal, a[i])];
  final x = a.sublist(start, endA);
  final y = b.sublist(start, endB);
  final n = x.length, m = y.length;
  if (n == 0) return [...prefix, for (final e in y) DiffEdit(DiffOp.insert, e), ...suffix];
  if (m == 0) return [...prefix, for (final e in x) DiffEdit(DiffOp.delete, e), ...suffix];

  final max = n + m;
  final offset = max;
  var v = List<int>.filled(2 * max + 2, 0);
  final trace = <List<int>>[];
  var found = false;
  for (var d = 0; d <= max && !found; d++) {
    trace.add(List<int>.of(v));
    for (var k = -d; k <= d; k += 2) {
      int xi;
      if (k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])) {
        xi = v[offset + k + 1];
      } else {
        xi = v[offset + k - 1] + 1;
      }
      var yi = xi - k;
      while (xi < n && yi < m && eq(x[xi], y[yi])) {
        xi++;
        yi++;
      }
      v[offset + k] = xi;
      if (xi >= n && yi >= m) {
        found = true;
        break;
      }
    }
  }

  // Backtrack.
  final edits = <DiffEdit<T>>[];
  var xi = n, yi = m;
  for (var d = trace.length - 1; d > 0; d--) {
    final vd = trace[d];
    final k = xi - yi;
    final prevK = (k == -d || (k != d && vd[offset + k - 1] < vd[offset + k + 1])) ? k + 1 : k - 1;
    final prevX = vd[offset + prevK];
    final prevY = prevX - prevK;
    while (xi > prevX && yi > prevY) {
      edits.add(DiffEdit(DiffOp.equal, x[--xi]));
      yi--;
    }
    if (xi == prevX) {
      edits.add(DiffEdit(DiffOp.insert, y[--yi]));
    } else {
      edits.add(DiffEdit(DiffOp.delete, x[--xi]));
    }
  }
  while (xi > 0 && yi > 0) {
    edits.add(DiffEdit(DiffOp.equal, x[--xi]));
    yi--;
  }
  return [...prefix, ...edits.reversed, ...suffix];
}

/// One row of a side-by-side view. Null side = blank filler.
@immutable
class DiffRow {
  const DiffRow({this.left, this.right, this.leftNo, this.rightNo, required this.kind});
  final String? left;
  final String? right;
  final int? leftNo;
  final int? rightNo;
  final DiffOp? kind; // null = modified (paired delete + insert)

  bool get changed => kind != DiffOp.equal;
}

@immutable
class TextDiffResult {
  const TextDiffResult(this.rows, {required this.added, required this.removed, required this.modified});
  final List<DiffRow> rows;
  final int added;
  final int removed;
  final int modified;

  bool get identical => added == 0 && removed == 0 && modified == 0;
}

/// Line-level side-by-side diff. Runs of deletions followed by insertions are
/// paired into "modified" rows so the view lines up.
TextDiffResult diffLines(
  String a,
  String b, {
  bool ignoreWhitespace = false,
  bool ignoreCase = false,
}) {
  String norm(String s) {
    var t = s;
    if (ignoreWhitespace) t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (ignoreCase) t = t.toLowerCase();
    return t;
  }

  final la = a.isEmpty ? <String>[] : a.split(RegExp(r'\r?\n'));
  final lb = b.isEmpty ? <String>[] : b.split(RegExp(r'\r?\n'));
  // Diff indices so we can recover original text with normalized comparison.
  final ia = List<int>.generate(la.length, (i) => i);
  final ib = List<int>.generate(lb.length, (i) => -1 - i);
  final na = la.map(norm).toList();
  final nb = lb.map(norm).toList();
  String keyOf(int i) => i >= 0 ? na[i] : nb[-1 - i];
  final edits = myersDiff<int>(
    [...ia],
    [...ib],
    equals: (p, q) => keyOf(p) == keyOf(q),
  );

  final rows = <DiffRow>[];
  var l = 0, r = 0, added = 0, removed = 0, modified = 0;
  final dels = <String>[];
  final ins = <String>[];
  void flush() {
    final pairs = dels.length < ins.length ? dels.length : ins.length;
    for (var i = 0; i < pairs; i++) {
      rows.add(DiffRow(left: dels[i], right: ins[i], leftNo: ++l, rightNo: ++r, kind: null));
      modified++;
    }
    for (var i = pairs; i < dels.length; i++) {
      rows.add(DiffRow(left: dels[i], leftNo: ++l, kind: DiffOp.delete));
      removed++;
    }
    for (var i = pairs; i < ins.length; i++) {
      rows.add(DiffRow(right: ins[i], rightNo: ++r, kind: DiffOp.insert));
      added++;
    }
    dels.clear();
    ins.clear();
  }

  for (final e in edits) {
    switch (e.op) {
      case DiffOp.equal:
        flush();
        // For equal edits `item` is from `a` (index >= 0).
        final left = la[e.item];
        final right = lb[r];
        rows.add(DiffRow(left: left, right: right, leftNo: ++l, rightNo: ++r, kind: DiffOp.equal));
      case DiffOp.delete:
        dels.add(la[e.item]);
      case DiffOp.insert:
        ins.add(lb[-1 - e.item]);
    }
  }
  flush();
  return TextDiffResult(rows, added: added, removed: removed, modified: modified);
}

/// Character-level diff of two lines, as (op, text) segments.
List<(DiffOp, String)> diffChars(String a, String b) {
  // Word-ish tokens read better than single characters for prose and code.
  final tokenizer = RegExp(r'\w+|\s+|[^\w\s]');
  final ta = [for (final m in tokenizer.allMatches(a)) m[0]!];
  final tb = [for (final m in tokenizer.allMatches(b)) m[0]!];
  final edits = myersDiff(ta, tb);
  final out = <(DiffOp, String)>[];
  for (final e in edits) {
    if (out.isNotEmpty && out.last.$1 == e.op) {
      out[out.length - 1] = (e.op, out.last.$2 + e.item);
    } else {
      out.add((e.op, e.item));
    }
  }
  return out;
}

/// Unified diff text (`diff -u` style) for copying.
String unifiedDiff(TextDiffResult result, {String from = 'a', String to = 'b'}) {
  final buf = StringBuffer('--- $from\n+++ $to\n');
  for (final row in result.rows) {
    switch (row.kind) {
      case DiffOp.equal:
        buf.writeln(' ${row.left}');
      case DiffOp.delete:
        buf.writeln('-${row.left}');
      case DiffOp.insert:
        buf.writeln('+${row.right}');
      case null:
        buf
          ..writeln('-${row.left}')
          ..writeln('+${row.right}');
    }
  }
  return buf.toString();
}

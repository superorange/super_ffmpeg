import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A JSON syntax error with a human position.
@immutable
class JsonError {
  const JsonError(this.message, {this.line, this.column, this.offset});
  final String message;
  final int? line;
  final int? column;
  final int? offset;

  @override
  String toString() => line == null ? message : '$message (line $line, column $column)';
}

/// Result of parsing: either a value or an error.
@immutable
class JsonParse {
  const JsonParse.ok(this.value) : error = null;
  const JsonParse.fail(this.error) : value = null;
  final Object? value;
  final JsonError? error;
  bool get ok => error == null;
}

abstract final class JsonTools {
  static JsonParse parse(String text) {
    if (text.trim().isEmpty) return const JsonParse.fail(JsonError('empty'));
    try {
      return JsonParse.ok(jsonDecode(text));
    } on FormatException catch (e) {
      final offset = e.offset;
      if (offset == null) return JsonParse.fail(JsonError(_clean(e.message)));
      final (line, col) = lineCol(text, offset);
      return JsonParse.fail(JsonError(_clean(e.message), line: line, column: col, offset: offset));
    }
  }

  static String _clean(String m) => m.replaceFirst(RegExp(r'^Unexpected character'), 'Unexpected character');

  /// 1-based line and column of [offset] in [text].
  static (int, int) lineCol(String text, int offset) {
    var line = 1, col = 1;
    final end = offset.clamp(0, text.length);
    for (var i = 0; i < end; i++) {
      if (text.codeUnitAt(i) == 10) {
        line++;
        col = 1;
      } else {
        col++;
      }
    }
    return (line, col);
  }

  /// [indent] = number of spaces, or 0 for a tab.
  static String format(Object? value, {int indent = 2, bool sortKeys = false}) {
    final v = sortKeys ? sortDeep(value) : value;
    return JsonEncoder.withIndent(indent == 0 ? '\t' : ' ' * indent).convert(v);
  }

  static String minify(Object? value, {bool sortKeys = false}) => jsonEncode(sortKeys ? sortDeep(value) : value);

  static Object? sortDeep(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => '$k').toList()..sort();
      return {for (final k in keys) k: sortDeep(v[k])};
    }
    if (v is List) return [for (final e in v) sortDeep(e)];
    return v;
  }

  /// Turns text into a JSON string literal (with quotes).
  static String escape(String text) => jsonEncode(text);

  /// Parses a JSON string literal (quotes optional) back to raw text.
  static String unescape(String text) {
    var t = text.trim();
    if (!(t.startsWith('"') && t.endsWith('"') && t.length >= 2)) t = '"$t"';
    final v = jsonDecode(t);
    if (v is! String) throw const FormatException('Not a JSON string');
    return v;
  }

  static String typeName(Object? v) => switch (v) {
    null => 'null',
    bool() => 'boolean',
    num() => 'number',
    String() => 'string',
    List() => 'array',
    Map() => 'object',
    _ => v.runtimeType.toString(),
  };

  /// Counts of keys/values for the status bar.
  static ({int objects, int arrays, int values, int depth}) stats(Object? v) {
    var objects = 0, arrays = 0, values = 0, depth = 0;
    void walk(Object? x, int d) {
      if (d > depth) depth = d;
      if (x is Map) {
        objects++;
        for (final e in x.values) {
          walk(e, d + 1);
        }
      } else if (x is List) {
        arrays++;
        for (final e in x) {
          walk(e, d + 1);
        }
      } else {
        values++;
      }
    }

    walk(v, 0);
    return (objects: objects, arrays: arrays, values: values, depth: depth);
  }

  /// Minimal JSONPath-style query: `$.a.b[0]`, `a.b`, `items[*].name`,
  /// `['key with space']`. Returns every match.
  static List<Object?> query(Object? root, String path) {
    var p = path.trim();
    if (p.isEmpty || p == r'$') return [root];
    if (p.startsWith(r'$')) p = p.substring(1);
    final tokens = <Object>[]; // String key, int index, or '*'
    final re = RegExp(r"""\.?([A-Za-z_$一-鿿][\w$一-鿿-]*)|\[(\d+|\*)\]|\[['"]((?:[^'"\\]|\\.)*)['"]\]|\.(\*)""");
    var pos = 0;
    while (pos < p.length) {
      final m = re.matchAsPrefix(p, pos);
      if (m == null) throw FormatException('Invalid path near "${p.substring(pos)}"');
      if (m[1] != null) {
        tokens.add(m[1]!);
      } else if (m[2] != null) {
        tokens.add(m[2] == '*' ? const _Wild() : int.parse(m[2]!));
      } else if (m[3] != null) {
        tokens.add(m[3]!);
      } else {
        tokens.add(const _Wild());
      }
      pos = m.end;
    }
    var current = <Object?>[root];
    for (final t in tokens) {
      final next = <Object?>[];
      for (final c in current) {
        if (t is _Wild) {
          if (c is List) next.addAll(c);
          if (c is Map) next.addAll(c.values);
        } else if (t is int) {
          if (c is List && t < c.length) next.add(c[t]);
        } else if (c is Map && c.containsKey(t)) {
          next.add(c[t]);
        }
      }
      current = next;
    }
    return current;
  }
}

class _Wild {
  const _Wild();
}

/// A structural difference between two JSON documents.
@immutable
class JsonChange {
  const JsonChange(this.kind, this.path, {this.before, this.after});
  final JsonChangeKind kind;
  final String path;
  final Object? before;
  final Object? after;
}

enum JsonChangeKind { added, removed, changed, typeChanged }

/// Deep comparison; object key order is ignored, array order is not.
List<JsonChange> jsonDiff(Object? a, Object? b, [String path = r'$']) {
  final out = <JsonChange>[];
  void walk(Object? x, Object? y, String p) {
    if (x is Map && y is Map) {
      for (final k in x.keys) {
        final kp = _join(p, '$k');
        if (!y.containsKey(k)) {
          out.add(JsonChange(JsonChangeKind.removed, kp, before: x[k]));
        } else {
          walk(x[k], y[k], kp);
        }
      }
      for (final k in y.keys) {
        if (!x.containsKey(k)) out.add(JsonChange(JsonChangeKind.added, _join(p, '$k'), after: y[k]));
      }
    } else if (x is List && y is List) {
      final n = x.length > y.length ? x.length : y.length;
      for (var i = 0; i < n; i++) {
        final ip = '$p[$i]';
        if (i >= x.length) {
          out.add(JsonChange(JsonChangeKind.added, ip, after: y[i]));
        } else if (i >= y.length) {
          out.add(JsonChange(JsonChangeKind.removed, ip, before: x[i]));
        } else {
          walk(x[i], y[i], ip);
        }
      }
    } else if (JsonTools.typeName(x) != JsonTools.typeName(y)) {
      out.add(JsonChange(JsonChangeKind.typeChanged, p, before: x, after: y));
    } else if (x != y) {
      out.add(JsonChange(JsonChangeKind.changed, p, before: x, after: y));
    }
  }

  walk(a, b, path);
  return out;
}

String _join(String parent, String key) =>
    RegExp(r'^[A-Za-z_$][\w$]*$').hasMatch(key) ? '$parent.$key' : '$parent[${jsonEncode(key)}]';

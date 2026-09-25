import 'dart:convert';

import 'package:yaml/yaml.dart';

/// YAML ⇄ JSON and CSV ⇄ JSON conversions.
abstract final class DataConvert {
  /// Parses YAML (all documents; one document → that value).
  static Object? yamlToValue(String text) {
    final docs = loadYamlDocuments(text);
    final values = [for (final d in docs) _plain(d.contents)];
    if (values.isEmpty) return null;
    return values.length == 1 ? values.single : values;
  }

  static Object? _plain(Object? node) {
    if (node is YamlScalar) return _plain(node.value);
    if (node is YamlMap || node is Map) {
      final m = node as Map;
      return {for (final e in m.entries) '${_plain(e.key)}': _plain(e.value)};
    }
    if (node is YamlList || node is List) return [for (final e in node as List) _plain(e)];
    if (node is double && (node.isNaN || node.isInfinite)) return node.toString();
    return node;
  }

  /// Emits block-style YAML for a JSON-compatible value.
  static String valueToYaml(Object? value, {int indent = 2}) {
    final pad = ' ' * indent;
    bool isBlock(Object? v) => (v is Map && v.isNotEmpty) || (v is List && v.isNotEmpty);
    String inline(Object? v, String contentIndent) => v is Map
        ? '{}'
        : v is List
        ? '[]'
        : _scalar(v, contentIndent);

    List<String> block(Object? v, int level) {
      final ind = pad * level;
      final lines = <String>[];
      if (v is Map) {
        for (final e in v.entries) {
          final key = _yamlKey('${e.key}');
          if (isBlock(e.value)) {
            lines
              ..add('$ind$key:')
              ..addAll(block(e.value, level + 1));
          } else {
            lines.add('$ind$key: ${inline(e.value, ind + pad)}');
          }
        }
      } else if (v is List) {
        for (final item in v) {
          if (isBlock(item)) {
            final child = block(item, level + 1);
            lines
              ..add('$ind- ${child.first.substring(ind.length + pad.length)}')
              ..addAll(child.skip(1));
          } else {
            lines.add('$ind- ${inline(item, ind + pad)}');
          }
        }
      }
      return lines;
    }

    if (!isBlock(value)) return '${inline(value, pad)}\n';
    return '${block(value, 0).join('\n')}\n';
  }

  static final _plainKey = RegExp(r'^[A-Za-z_][\w.-]*$');
  static String _yamlKey(String k) => _plainKey.hasMatch(k) && !_reserved.contains(k.toLowerCase()) ? k : jsonEncode(k);

  static const _reserved = {'true', 'false', 'yes', 'no', 'on', 'off', 'null', '~', 'y', 'n'};

  static String _scalar(Object? v, String indent) {
    if (v == null) return 'null';
    if (v is bool || v is num) return '$v';
    final s = '$v';
    if (s.contains('\n')) {
      final lines = s.split('\n');
      final keep = s.endsWith('\n') ? '' : '-';
      final body = (s.endsWith('\n') ? lines.sublist(0, lines.length - 1) : lines)
          .map((l) => l.isEmpty ? '' : '$indent$l')
          .join('\n');
      return '|$keep\n$body';
    }
    final needsQuote =
        s.isEmpty ||
        _reserved.contains(s.toLowerCase()) ||
        num.tryParse(s) != null ||
        RegExp(r'''^[\s\-?:,\[\]{}#&*!|>'"%@`]|: |\s#|\s$''').hasMatch(s);
    return needsQuote ? jsonEncode(s) : s;
  }

  /// RFC 4180 CSV parser (quoted fields, escaped quotes, CRLF).
  static List<List<String>> parseCsv(String text, {String delimiter = ','}) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var quoted = false;
    var i = 0;
    final d = delimiter.codeUnitAt(0);
    while (i < text.length) {
      final ch = text.codeUnitAt(i);
      if (quoted) {
        if (ch == 0x22) {
          if (i + 1 < text.length && text.codeUnitAt(i + 1) == 0x22) {
            field.write('"');
            i += 2;
            continue;
          }
          quoted = false;
        } else {
          field.writeCharCode(ch);
        }
      } else if (ch == 0x22 && field.isEmpty) {
        quoted = true;
      } else if (ch == d) {
        row.add(field.toString());
        field.clear();
      } else if (ch == 0x0A || ch == 0x0D) {
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <String>[];
        if (ch == 0x0D && i + 1 < text.length && text.codeUnitAt(i + 1) == 0x0A) i++;
      } else {
        field.writeCharCode(ch);
      }
      i++;
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }

  /// CSV with a header row → list of objects. Numbers/booleans are typed
  /// when [inferTypes] is set.
  static List<Map<String, Object?>> csvToObjects(String text, {String delimiter = ',', bool inferTypes = true}) {
    final rows = parseCsv(text, delimiter: delimiter).where((r) => !(r.length == 1 && r.single.isEmpty)).toList();
    if (rows.isEmpty) return const [];
    final header = rows.first;
    Object? typed(String s) {
      if (!inferTypes) return s;
      if (s == 'true') return true;
      if (s == 'false') return false;
      if (s.isEmpty) return '';
      if (RegExp(r'^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?$').hasMatch(s)) return num.parse(s);
      return s;
    }

    return [
      for (final r in rows.skip(1))
        {for (var c = 0; c < header.length; c++) header[c]: c < r.length ? typed(r[c]) : null},
    ];
  }

  /// Array of objects (or arrays) → CSV; columns are the union of keys.
  static String valueToCsv(Object? value, {String delimiter = ','}) {
    if (value is! List) throw const FormatException('Expected a JSON array');
    String cell(Object? v) {
      final s = v == null ? '' : (v is Map || v is List ? jsonEncode(v) : '$v');
      return s.contains(delimiter) || s.contains('"') || s.contains('\n') || s.contains('\r')
          ? '"${s.replaceAll('"', '""')}"'
          : s;
    }

    final buf = StringBuffer();
    if (value.every((e) => e is List)) {
      for (final r in value.cast<List>()) {
        buf.writeln(r.map(cell).join(delimiter));
      }
      return buf.toString();
    }
    final cols = <String>[];
    for (final e in value) {
      if (e is! Map) throw const FormatException('Expected an array of objects');
      for (final k in e.keys) {
        if (!cols.contains('$k')) cols.add('$k');
      }
    }
    buf.writeln(cols.map(cell).join(delimiter));
    for (final e in value.cast<Map>()) {
      buf.writeln([for (final c in cols) cell(e[c])].join(delimiter));
    }
    return buf.toString();
  }
}

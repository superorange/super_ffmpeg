/// Generates typed models from a JSON sample.
enum CodeTarget { typescript, dart, go, swift, kotlin }

sealed class _T {
  const _T();
}

class _Prim extends _T {
  const _Prim(this.kind);
  final String kind; // string | int | double | bool
}

class _Null extends _T {
  const _Null();
}

class _Any extends _T {
  const _Any();
}

class _List extends _T {
  _List(this.elem);
  _T elem;
}

class _Obj extends _T {
  _Obj(this.name);
  String name;
  final fields = <String, _T>{};
  final optional = <String>{};
  final nullable = <String>{};
}

class JsonCodegen {
  JsonCodegen({this.rootName = 'Root'});
  final String rootName;
  final _classes = <_Obj>[];
  final _names = <String>{};

  String generate(Object? json, CodeTarget target) {
    _classes.clear();
    _names.clear();
    final root = _infer(json, rootName);
    if (root is! _Obj) {
      // Top-level array/primitive: model its element and alias the root.
      final alias = _typeName(root, target);
      final body = _emitAll(target);
      return switch (target) {
        CodeTarget.typescript => '${body}export type $rootName = $alias;\n',
        CodeTarget.dart => '$body// typedef $rootName = $alias;\n',
        CodeTarget.go => '${body}type $rootName $alias\n',
        CodeTarget.swift => '${body}typealias $rootName = $alias\n',
        CodeTarget.kotlin => '${body}typealias $rootName = $alias\n',
      };
    }
    return _emitAll(target);
  }

  String _unique(String base) {
    var name = base.isEmpty ? 'Item' : base;
    var i = 2;
    while (_names.contains(name)) {
      name = '$base${i++}';
    }
    _names.add(name);
    return name;
  }

  _T _infer(Object? v, String nameHint) {
    if (v == null) return const _Null();
    if (v is bool) return const _Prim('bool');
    if (v is int) return const _Prim('int');
    if (v is double) return v == v.roundToDouble() && v.abs() < 1e15 ? const _Prim('double') : const _Prim('double');
    if (v is num) return const _Prim('double');
    if (v is String) return const _Prim('string');
    if (v is List) {
      _T? elem;
      final itemName = _singular(nameHint);
      for (final e in v) {
        elem = elem == null ? _infer(e, itemName) : _merge(elem, _infer(e, itemName));
      }
      return _List(elem ?? const _Any());
    }
    if (v is Map) {
      final obj = _Obj(_unique(_pascal(nameHint)));
      _classes.add(obj);
      for (final e in v.entries) {
        final key = '${e.key}';
        final t = _infer(e.value, key);
        if (t is _Null) obj.nullable.add(key);
        obj.fields[key] = t;
      }
      return obj;
    }
    return const _Any();
  }

  _T _merge(_T a, _T b) {
    if (a is _Null) return b;
    if (b is _Null) return a;
    if (a is _Prim && b is _Prim) {
      if (a.kind == b.kind) return a;
      if ({a.kind, b.kind}.containsAll(['int', 'double'])) return const _Prim('double');
      return const _Any();
    }
    if (a is _List && b is _List) return _List(_merge(a.elem, b.elem));
    if (a is _Obj && b is _Obj) {
      for (final k in {...a.fields.keys, ...b.fields.keys}) {
        final ta = a.fields[k], tb = b.fields[k];
        if (ta == null || tb == null) a.optional.add(k);
        if (ta is _Null || tb is _Null) a.nullable.add(k);
        a.fields[k] = ta == null ? tb! : (tb == null ? ta : _merge(ta, tb));
      }
      a.optional.addAll(b.optional);
      a.nullable.addAll(b.nullable);
      _classes.remove(b);
      _names.remove(b.name);
      return a;
    }
    return const _Any();
  }

  String _emitAll(CodeTarget target) {
    final buf = StringBuffer();
    if (target == CodeTarget.dart) {
      // no imports needed
    }
    if (target == CodeTarget.kotlin) buf.writeln('import kotlinx.serialization.*\n');
    for (final c in _classes) {
      buf
        ..write(_emit(c, target))
        ..writeln();
    }
    return buf.toString();
  }

  String _typeName(_T t, CodeTarget target, {bool nullable = false}) {
    final base = switch (t) {
      _Prim(:final kind) => switch (target) {
        CodeTarget.typescript => kind == 'string' ? 'string' : (kind == 'bool' ? 'boolean' : 'number'),
        CodeTarget.dart => {'string': 'String', 'int': 'int', 'double': 'double', 'bool': 'bool'}[kind]!,
        CodeTarget.go => {'string': 'string', 'int': 'int64', 'double': 'float64', 'bool': 'bool'}[kind]!,
        CodeTarget.swift => {'string': 'String', 'int': 'Int', 'double': 'Double', 'bool': 'Bool'}[kind]!,
        CodeTarget.kotlin => {'string': 'String', 'int': 'Long', 'double': 'Double', 'bool': 'Boolean'}[kind]!,
      },
      _List(:final elem) => switch (target) {
        CodeTarget.typescript => _arrayTs(_typeName(elem, target)),
        CodeTarget.dart => 'List<${_typeName(elem, target)}>',
        CodeTarget.go => '[]${_typeName(elem, target)}',
        CodeTarget.swift => '[${_typeName(elem, target)}]',
        CodeTarget.kotlin => 'List<${_typeName(elem, target)}>',
      },
      _Obj(:final name) => name,
      _Null() || _Any() => switch (target) {
        CodeTarget.typescript => t is _Null ? 'null' : 'unknown',
        CodeTarget.dart => 'dynamic',
        CodeTarget.go => 'any',
        CodeTarget.swift => 'AnyCodable',
        CodeTarget.kotlin => 'kotlinx.serialization.json.JsonElement',
      },
    };
    if (!nullable || t is _Null || t is _Any && target == CodeTarget.dart) return base;
    return switch (target) {
      CodeTarget.typescript => '$base | null',
      CodeTarget.dart || CodeTarget.swift || CodeTarget.kotlin => '$base?',
      CodeTarget.go => t is _Obj ? '*$base' : base,
    };
  }

  static String _arrayTs(String elem) => elem.contains(' ') ? '($elem)[]' : '$elem[]';

  String _emit(_Obj c, CodeTarget target) {
    final buf = StringBuffer();
    final entries = c.fields.entries.toList();
    switch (target) {
      case CodeTarget.typescript:
        buf.writeln('export interface ${c.name} {');
        for (final e in entries) {
          final key = RegExp(r'^[A-Za-z_$][\w$]*$').hasMatch(e.key) ? e.key : "'${e.key}'";
          final opt = c.optional.contains(e.key) ? '?' : '';
          buf.writeln('  $key$opt: ${_typeName(e.value, target, nullable: c.nullable.contains(e.key))};');
        }
        buf.writeln('}');
      case CodeTarget.dart:
        buf.writeln('class ${c.name} {');
        final fields = [
          for (final e in entries)
            (
              e.key,
              _safeIdent(_camel(e.key)),
              _typeName(e.value, target, nullable: c.nullable.contains(e.key) || c.optional.contains(e.key)),
              e.value,
            ),
        ];
        buf.writeln('  const ${c.name}({');
        for (final f in fields) {
          buf.writeln('    ${f.$3.endsWith('?') || f.$3 == 'dynamic' ? '' : 'required '}this.${f.$2},');
        }
        buf.writeln('  });\n');
        buf.writeln('  factory ${c.name}.fromJson(Map<String, dynamic> json) => ${c.name}(');
        for (final f in fields) {
          buf.writeln('    ${f.$2}: ${_dartFrom("json['${f.$1}']", f.$4, f.$3.endsWith('?'))},');
        }
        buf.writeln('  );\n');
        for (final f in fields) {
          buf.writeln('  final ${f.$3} ${f.$2};');
        }
        buf.writeln('\n  Map<String, dynamic> toJson() => {');
        for (final f in fields) {
          buf.writeln("    '${f.$1}': ${_dartTo(f.$2, f.$4, f.$3.endsWith('?'))},");
        }
        buf.writeln('  };');
        buf.writeln('}');
      case CodeTarget.go:
        buf.writeln('type ${c.name} struct {');
        for (final e in entries) {
          final omit = c.optional.contains(e.key) ? ',omitempty' : '';
          buf.writeln(
            '\t${_goIdent(e.key)} ${_typeName(e.value, target, nullable: c.nullable.contains(e.key))} `json:"${e.key}$omit"`',
          );
        }
        buf.writeln('}');
      case CodeTarget.swift:
        buf.writeln('struct ${c.name}: Codable {');
        final renamed = <String, String>{};
        for (final e in entries) {
          final name = _safeIdent(_camel(e.key));
          if (name != e.key) renamed[name] = e.key;
          final opt = c.nullable.contains(e.key) || c.optional.contains(e.key);
          buf.writeln('    let $name: ${_typeName(e.value, target, nullable: opt)}');
        }
        if (renamed.isNotEmpty) {
          buf.writeln('\n    enum CodingKeys: String, CodingKey {');
          for (final e in entries) {
            final name = _safeIdent(_camel(e.key));
            buf.writeln(renamed.containsKey(name) ? '        case $name = "${e.key}"' : '        case $name');
          }
          buf.writeln('    }');
        }
        buf.writeln('}');
      case CodeTarget.kotlin:
        buf.writeln('@Serializable');
        buf.writeln('data class ${c.name}(');
        for (final e in entries) {
          final name = _safeIdent(_camel(e.key));
          final opt = c.nullable.contains(e.key) || c.optional.contains(e.key);
          final ann = name != e.key ? '@SerialName("${e.key}") ' : '';
          buf.writeln('    ${ann}val $name: ${_typeName(e.value, target, nullable: opt)}${opt ? ' = null' : ''},');
        }
        buf.writeln(')');
    }
    return buf.toString();
  }

  String _dartFrom(String expr, _T t, bool nullable) {
    final q = nullable ? '?' : '';
    return switch (t) {
      _Prim(kind: 'double') => '($expr as num$q)$q.toDouble()',
      _Prim(:final kind) => '$expr as ${{'string': 'String', 'int': 'int', 'bool': 'bool'}[kind]}$q',
      _Obj(:final name) =>
        nullable
            ? '$expr == null ? null : $name.fromJson($expr as Map<String, dynamic>)'
            : '$name.fromJson($expr as Map<String, dynamic>)',
      _List(:final elem) => '($expr as List$q)$q.map((e) => ${_dartFrom('e', elem, false)}).toList()',
      _ => expr,
    };
  }

  String _dartTo(String name, _T t, bool nullable) {
    final q = nullable ? '?' : '';
    return switch (t) {
      _Obj() => '$name$q.toJson()',
      _List(elem: _Obj()) => '$name$q.map((e) => e.toJson()).toList()',
      _ => name,
    };
  }

  static String _pascal(String s) {
    final words = s.split(RegExp(r'[^A-Za-z0-9]+|(?<=[a-z0-9])(?=[A-Z])')).where((w) => w.isNotEmpty);
    final out = words.map((w) => w[0].toUpperCase() + w.substring(1)).join();
    if (out.isEmpty) return 'Item';
    return RegExp(r'^\d').hasMatch(out) ? 'T$out' : out;
  }

  static String _camel(String s) {
    final p = _pascal(s);
    return p[0].toLowerCase() + p.substring(1);
  }

  static String _goIdent(String s) {
    final p = _pascal(s);
    return p.replaceAllMapped(RegExp(r'(Id|Url|Uri|Http|Json|Api)(?=[A-Z]|$)'), (m) => m[1]!.toUpperCase());
  }

  static const _keywords = {
    'class',
    'default',
    'switch',
    'case',
    'new',
    'return',
    'this',
    'var',
    'final',
    'const',
    'is',
    'in',
    'enum',
    'extends',
    'import',
    'let',
    'struct',
    'func',
    'type',
    'package',
    'val',
    'fun',
    'object',
    'when',
    'if',
    'else',
  };

  static String _safeIdent(String s) => _keywords.contains(s) ? '${s}Value' : s;

  static String _singular(String s) {
    if (s.endsWith('ies') && s.length > 3) return '${s.substring(0, s.length - 3)}y';
    if (s.endsWith('ses') || s.endsWith('xes')) return s.substring(0, s.length - 2);
    if (s.endsWith('s') && !s.endsWith('ss') && s.length > 1) return s.substring(0, s.length - 1);
    return '${s}Item';
  }
}

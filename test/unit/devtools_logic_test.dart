import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_ffmpeg/modules/data/logic/converters.dart';
import 'package:super_ffmpeg/modules/data/logic/json_codegen.dart';
import 'package:super_ffmpeg/modules/data/logic/json_tools.dart';
import 'package:super_ffmpeg/modules/encode/logic/codecs.dart';
import 'package:super_ffmpeg/modules/encode/logic/hashing.dart';
import 'package:super_ffmpeg/modules/encode/logic/jwt.dart';
import 'package:super_ffmpeg/modules/encode/logic/number_base.dart';
import 'package:super_ffmpeg/modules/generate/logic/generators.dart';
import 'package:super_ffmpeg/modules/generate/logic/time_tools.dart';
import 'package:super_ffmpeg/modules/text/logic/diff.dart';
import 'package:super_ffmpeg/modules/text/logic/text_tools.dart';
import 'package:super_ffmpeg/modules/web/logic/color_tools.dart';

void main() {
  group('JSON', () {
    test('formats, sorts and minifies', () {
      final v = JsonTools.parse('{"b":1,"a":[true,null]}').value;
      expect(JsonTools.format(v, indent: 2, sortKeys: true), '{\n  "a": [\n    true,\n    null\n  ],\n  "b": 1\n}');
      expect(JsonTools.minify(v), '{"b":1,"a":[true,null]}');
      expect(JsonTools.format(v, indent: 0).split('\n')[1], startsWith('\t'));
    });

    test('reports line and column of syntax errors', () {
      final r = JsonTools.parse('{\n  "a": 1,\n  "b": ]\n}');
      expect(r.ok, isFalse);
      expect(r.error!.line, 3);
      expect(r.error!.column, 8);
    });

    test('escape round-trips', () {
      const raw = 'line1\n"quoted" \\ tab\t中文';
      expect(JsonTools.unescape(JsonTools.escape(raw)), raw);
      expect(JsonTools.unescape(r'a\nb'), 'a\nb');
    });

    test('query supports paths, wildcards and quoted keys', () {
      final v = jsonDecode('{"items":[{"name":"a"},{"name":"b"}],"odd key":{"x":1}}');
      expect(JsonTools.query(v, r'$.items[*].name'), ['a', 'b']);
      expect(JsonTools.query(v, 'items[1].name'), ['b']);
      expect(JsonTools.query(v, r"$['odd key'].x"), [1]);
      expect(JsonTools.query(v, 'missing'), isEmpty);
    });

    test('structural diff ignores key order', () {
      final a = jsonDecode('{"a":1,"b":{"c":[1,2]},"d":"x"}');
      final b = jsonDecode('{"b":{"c":[1,3,4]},"a":1,"e":true,"d":5}');
      final changes = {for (final c in jsonDiff(a, b)) c.path: c.kind};
      expect(changes, {
        r'$.b.c[1]': JsonChangeKind.changed,
        r'$.b.c[2]': JsonChangeKind.added,
        r'$.d': JsonChangeKind.typeChanged,
        r'$.e': JsonChangeKind.added,
      });
      expect(jsonDiff(a, a), isEmpty);
    });
  });

  group('YAML / CSV', () {
    test('JSON → YAML → JSON round-trips', () {
      final v = jsonDecode(
        '{"name":"app","version":1.5,"on":true,"tags":["a","b: c"],"nested":{"list":[{"x":1,"y":[1,2]},[3,4]],'
        '"empty":{},"none":[]},"text":"multi\\nline","n":null,"num_str":"123"}',
      );
      final yaml = DataConvert.valueToYaml(v);
      expect(yaml, contains('tags:\n  - a\n  - "b: c"'));
      expect(yaml, contains('"on": true'));
      expect(yaml, contains('num_str: "123"'));
      expect(DataConvert.yamlToValue(yaml), v);
    });

    test('parses YAML documents', () {
      expect(DataConvert.yamlToValue('a: 1\nb:\n  - x\n  - y\n'), {
        'a': 1,
        'b': ['x', 'y'],
      });
      expect(DataConvert.yamlToValue('---\na: 1\n---\nb: 2\n'), [
        {'a': 1},
        {'b': 2},
      ]);
    });

    test('CSV with quotes and CRLF', () {
      const csv = 'name,note,age\r\n"Doe, J","said ""hi""",42\r\nAnn,,7\r\n';
      final rows = DataConvert.csvToObjects(csv);
      expect(rows, [
        {'name': 'Doe, J', 'note': 'said "hi"', 'age': 42},
        {'name': 'Ann', 'note': '', 'age': 7},
      ]);
      final back = DataConvert.valueToCsv(rows);
      expect(back, 'name,note,age\n"Doe, J","said ""hi""",42\nAnn,,7\n');
    });
  });

  group('codegen', () {
    final sample = jsonDecode(
      '{"id":1,"user_name":"x","score":1.5,"tags":["a"],"address":{"city":"c"},'
      '"items":[{"sku":"a","qty":1},{"sku":"b","price":2.5}],"deleted_at":null}',
    );

    test('TypeScript marks optional and nullable fields', () {
      final ts = JsonCodegen().generate(sample, CodeTarget.typescript);
      expect(ts, contains('export interface Root {'));
      expect(ts, contains('  user_name: string;'));
      expect(ts, contains('  items: Item[];'));
      expect(ts, contains('  qty?: number;'));
      expect(ts, contains('  price?: number;'));
      expect(ts, contains('  deleted_at: null;'));
      expect(ts, contains('export interface Address {'));
    });

    test('Dart, Go, Swift, Kotlin', () {
      final dart = JsonCodegen().generate(sample, CodeTarget.dart);
      expect(dart, contains('final String userName;'));
      expect(dart, contains("userName: json['user_name'] as String,"));
      expect(dart, contains('final List<Item> items;'));
      expect(dart, contains('final int? qty;'));
      final go = JsonCodegen().generate(sample, CodeTarget.go);
      expect(go, contains('ID int64 `json:"id"`'));
      expect(go, contains('Qty int64 `json:"qty,omitempty"`'));
      final swift = JsonCodegen().generate(sample, CodeTarget.swift);
      expect(swift, contains('case userName = "user_name"'));
      final kt = JsonCodegen().generate(sample, CodeTarget.kotlin);
      expect(kt, contains('@SerialName("user_name") val userName: String,'));
    });
  });

  group('encodings', () {
    test('base64 variants and lenient decoding', () {
      expect(Codecs.encode(TextCodec.base64, '你好 world'), '5L2g5aW9IHdvcmxk');
      expect(Codecs.decode(TextCodec.base64, '5L2g5aW9IHdvcmxk'), '你好 world');
      expect(Codecs.encode(TextCodec.base64url, '??>>'), 'Pz8-Pg');
      expect(Codecs.decode(TextCodec.base64, 'Pz8-Pg'), '??>>');
      expect(Codecs.base64Decode('data:text/plain;base64,aGk='), utf8.encode('hi'));
    });

    test('url, html, unicode, hex, binary', () {
      expect(Codecs.encode(TextCodec.urlComponent, 'a b&c=中'), 'a%20b%26c%3D%E4%B8%AD');
      expect(Codecs.decode(TextCodec.urlComponent, 'a+b%26'), 'a b&');
      expect(Codecs.encode(TextCodec.html, '<a href="x">&</a>'), '&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;');
      expect(Codecs.decode(TextCodec.html, '&lt;&#39;&#x4E2D;&copy;&unknown;'), "<'中©&unknown;");
      expect(Codecs.encode(TextCodec.unicode, 'a中😀'), r'a\u4e2d\ud83d\ude00');
      expect(Codecs.decode(TextCodec.unicode, r'a\u4e2d\ud83d\ude00\u{1F600}\x41'), 'a中😀😀A');
      expect(Codecs.encode(TextCodec.hex, 'hi'), '6869');
      expect(Codecs.decode(TextCodec.hex, '0x68 69'), 'hi');
      expect(Codecs.encode(TextCodec.binary, 'A'), '01000001');
      expect(Codecs.decode(TextCodec.binary, '01000001 01000010'), 'AB');
    });

    test('url inspector keeps repeated params', () {
      final u = UrlParts.tryParse('https://a.com:8080/p/q?x=1&x=2&y=%E4%B8%AD#frag')!;
      expect(u.uri.host, 'a.com');
      expect(u.uri.port, 8080);
      expect(u.query, [('x', '1'), ('x', '2'), ('y', '中')]);
    });

    test('file signatures', () {
      expect(Codecs.sniff([0x89, 0x50, 0x4E, 0x47, 0])?.ext, 'png');
      expect(Codecs.sniff([1, 2, 3]), isNull);
    });
  });

  group('JWT', () {
    test('sign, decode and verify', () {
      final exp = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
      final token = Jwt.sign({'sub': '42', 'exp': exp}, 'secret');
      final d = Jwt.decode('Bearer $token');
      expect(d.alg, 'HS256');
      expect(d.claims['sub'], '42');
      expect(d.isExpired(), isFalse);
      expect(d.verify('secret'), JwtSignature.valid);
      expect(d.verify('wrong'), JwtSignature.invalid);
      expect(d.verify(''), JwtSignature.unchecked);
    });

    test('known HS256 vector (jwt.io)', () {
      const t =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.'
          'SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';
      final d = Jwt.decode(t);
      expect(d.claims['name'], 'John Doe');
      expect(d.issuedAt!.toUtc().year, 2018);
      expect(d.verify('your-256-bit-secret'), JwtSignature.valid);
    });

    test('rejects malformed tokens', () {
      expect(() => Jwt.decode('abc'), throwsFormatException);
      expect(() => Jwt.decode('a.b.c'), throwsFormatException);
    });
  });

  group('hashing', () {
    test('digests and HMAC', () {
      expect(Hashing.text(HashAlg.md5, 'abc'), '900150983cd24fb0d6963f7d28e17f72');
      expect(Hashing.text(HashAlg.sha256, 'abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(Hashing.text(HashAlg.crc32, 'The quick brown fox jumps over the lazy dog'), '414fa339');
      expect(
        Hashing.text(HashAlg.sha256, 'The quick brown fox jumps over the lazy dog', hmacKey: 'key'),
        'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8',
      );
    });
  });

  group('number base', () {
    test('parses prefixes and converts big numbers', () {
      expect(NumberBase.parse('0xff', 16), BigInt.from(255));
      expect(NumberBase.parse('1111_0000', 2), BigInt.from(240));
      expect(NumberBase.format(BigInt.parse('18446744073709551615'), 16), 'ffffffffffffffff');
      expect(NumberBase.format(BigInt.from(1234567), 10, group: true), '1,234,567');
      expect(NumberBase.twosComplement(BigInt.from(-1), 8), '11111111');
      expect(() => NumberBase.parse('12', 2), throwsFormatException);
      expect(NumberBase.parseWithRadix('0x1F4', 10), (BigInt.from(500), 16));
      expect(NumberBase.parse('0b1', 16), BigInt.from(0xb1), reason: '0b is hex digits in base 16');
    });
  });

  group('diff', () {
    test('myers minimal edit script', () {
      final e = myersDiff('ABCABBA'.split(''), 'CBABAC'.split(''));
      expect(e.where((x) => x.op != DiffOp.equal).length, 5);
      expect(e.where((x) => x.op != DiffOp.insert).map((x) => x.item).join(), 'ABCABBA');
      expect(e.where((x) => x.op != DiffOp.delete).map((x) => x.item).join(), 'CBABAC');
    });

    test('side-by-side rows pair modifications', () {
      final r = diffLines('a\nb\nc\nd', 'a\nB\nc\ne\nf');
      expect(r.modified, 2);
      expect(r.added, 1);
      expect(r.removed, 0);
      expect(r.rows.map((x) => x.kind), [DiffOp.equal, null, DiffOp.equal, null, DiffOp.insert]);
      expect(diffLines('x', 'x').identical, isTrue);
      expect(diffLines('a  b\nC', 'a b\nc', ignoreWhitespace: true, ignoreCase: true).identical, isTrue);
    });

    test('inline word diff', () {
      final segs = diffChars('the quick fox', 'the slow fox');
      expect(segs, [(DiffOp.equal, 'the '), (DiffOp.delete, 'quick'), (DiffOp.insert, 'slow'), (DiffOp.equal, ' fox')]);
    });
  });

  group('text', () {
    test('case conversion', () {
      const s = 'parseHTTPResponse v2';
      expect(TextTools.convertCase(s, CaseStyle.snake), 'parse_http_response_v_2');
      expect(TextTools.convertCase('hello world', CaseStyle.camel), 'helloWorld');
      expect(TextTools.convertCase('hello_world-foo', CaseStyle.pascal), 'HelloWorldFoo');
      expect(TextTools.convertCase('HelloWorld', CaseStyle.constant), 'HELLO_WORLD');
      expect(TextTools.convertCase('some title here', CaseStyle.title), 'Some Title Here');
    });

    test('stats count CJK characters as words', () {
      final s = TextTools.stats('Hello world.\n你好世界！');
      expect(s.words, 6);
      expect(s.lines, 2);
      expect(s.characters, 18);
      expect(s.bytes, 28);
    });

    test('line operations', () {
      expect(TextTools.applyLineOp('b\na\nb\n\nc', LineOp.unique), 'b\na\n\nc');
      expect(TextTools.applyLineOp('f10\nf2\nf1', LineOp.sortNatural), 'f1\nf2\nf10');
      expect(TextTools.applyLineOp(' x \n\n y', LineOp.joinLines), 'x y');
    });

    test('lorem is deterministic with a seed', () {
      expect(TextTools.lorem(seed: 1), TextTools.lorem(seed: 1));
      expect(TextTools.lorem(paragraphs: 2).split('\n\n'), hasLength(2));
      expect(TextTools.lorem(chinese: true, paragraphs: 1, sentences: 2), endsWith('。'));
    });
  });

  group('generators', () {
    test('uuid v4/v7, ulid, nanoid', () {
      expect(Ids.uuid4(), matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      final at = DateTime.fromMillisecondsSinceEpoch(1700000000123);
      final v7 = Ids.uuid7(at);
      expect(v7[14], '7');
      expect(Ids.timestampOf(v7), at);
      final u = Ids.ulid(at);
      expect(u, hasLength(26));
      expect(Ids.timestampOf(u), at);
      expect(Ids.nanoid(10), hasLength(10));
      expect(Ids.generate(IdKind.uuid4, hyphens: false, upper: true), matches(RegExp(r'^[0-9A-F]{32}$')));
      expect(Ids.objectId(), hasLength(24));
    });

    test('passwords include every enabled set', () {
      const o = PasswordOptions(length: 8, symbols: false);
      for (var i = 0; i < 50; i++) {
        final p = Passwords.generate(o);
        expect(p, hasLength(8));
        expect(p, matches(RegExp(r'[a-z]')));
        expect(p, matches(RegExp(r'[A-Z]')));
        expect(p, matches(RegExp(r'\d')));
      }
      expect(Passwords.entropy(const PasswordOptions(length: 10, upper: false, symbols: false)), closeTo(51.7, 0.1));
    });
  });

  group('time', () {
    test('guesses unix units and parses dates', () {
      expect(TimeTools.parse('1700000000')!.time.millisecondsSinceEpoch, 1700000000000);
      expect(TimeTools.parse('1700000000123')!.source, 'unix:milliseconds');
      expect(TimeTools.parse('2024-02-29 12:00:00')!.time, DateTime(2024, 2, 29, 12));
      expect(TimeTools.parse('2024-02-29T12:00:00Z')!.time, DateTime.utc(2024, 2, 29, 12));
      expect(TimeTools.parse('Thu, 29 Feb 2024 12:00:00 +0200')!.time, DateTime.utc(2024, 2, 29, 10));
      expect(TimeTools.parse('nonsense'), isNull);
      expect(TimeTools.rfc2822(DateTime.utc(2024, 2, 29, 10)), 'Thu, 29 Feb 2024 10:00:00 GMT');
      expect(TimeTools.isoWeek(DateTime(2021, 1, 3)), 53);
    });

    test('cron next runs', () {
      final from = DateTime(2026, 9, 25, 10, 7);
      final c = CronExpression.parse('*/15 9-17 * * MON-FRI');
      expect(c.next(3, from: from), [
        DateTime(2026, 9, 25, 10, 15),
        DateTime(2026, 9, 25, 10, 30),
        DateTime(2026, 9, 25, 10, 45),
      ]);
      // Friday 17:45 → next Monday 09:00.
      expect(c.next(1, from: DateTime(2026, 9, 25, 17, 45)).single, DateTime(2026, 9, 28, 9));
      expect(CronExpression.parse('@monthly').next(1, from: from).single, DateTime(2026, 10, 1));
      expect(() => CronExpression.parse('61 * * * *'), throwsFormatException);
      expect(() => CronExpression.parse('* * *'), throwsFormatException);
    });
  });

  group('color & css', () {
    test('parses and formats notations', () {
      final c = ColorTools.parse('#6554F0')!;
      expect(ColorTools.hex(c), '#6554F0');
      expect(ColorTools.rgb(c), 'rgb(101, 84, 240)');
      expect(ColorTools.parse('rgb(101 84 240)'), c);
      expect(ColorTools.hsl(c), 'hsl(247, 84%, 64%)');
      expect(ColorTools.parse('hsl(0, 100%, 50%)'), const Color(0xFFFF0000));
      expect(ColorTools.parse('hsv(120, 100%, 100%)'), const Color(0xFF00FF00));
      expect(ColorTools.hex(ColorTools.parse('#f00')!), '#FF0000');
      expect(ColorTools.rgb(ColorTools.parse('rgba(0,0,0,.5)')!), 'rgba(0, 0, 0, 0.5)');
      expect(ColorTools.parse('tomato'), const Color(0xFFFF6347));
      expect(ColorTools.contrast(const Color(0xFF000000), const Color(0xFFFFFFFF)), closeTo(21, 0.01));
      expect(ColorTools.scale(c), hasLength(11));
      expect(ColorTools.parse('nope'), isNull);
    });

    test('css format and minify', () {
      const css = '/* c */ a,b{color:red;margin:0 auto}@media (max-width:600px){.x{content:"a;b{"}}';
      final f = CssTools.format(css);
      expect(f, contains('a, b {\n  color: red;\n  margin: 0 auto;\n}'));
      expect(f, contains('@media (max-width:600px) {\n  .x {\n    content: "a;b{";\n  }\n}'));
      expect(CssTools.minify(f), 'a,b{color:red;margin:0 auto}@media (max-width:600px){.x{content:"a;b{"}}');
    });
  });
}

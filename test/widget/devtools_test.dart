import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_ffmpeg/core/toolbox/file_intake.dart';
import 'package:super_ffmpeg/ui/widgets/code_area.dart';

import 'harness.dart';

CodeLineEditingController _editor(WidgetTester tester, [int index = 0]) =>
    tester.widget<CodeArea>(find.byType(CodeArea).at(index)).controller;

Future<void> _type(WidgetTester tester, Finder field, String text) async {
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('JSON: formats, reports errors with position, queries', (tester) async {
    await pumpApp(tester, location: '/tool/json');
    expect(find.textContaining('Valid JSON'), findsOneWidget);
    expect(_editor(tester, 1).text, contains('"modules": [\n    "media"'));

    _editor(tester).text = '{\n  "a": 1,\n  "b": ]\n}';
    await tester.pumpAndSettle();
    expect(find.textContaining('line 3, column 8'), findsOneWidget);
    expect(find.text('Go to'), findsOneWidget);

    _editor(tester).text = '{"items":[{"n":"x"},{"n":"y"}]}';
    await tester.pumpAndSettle();
    await _type(tester, find.byType(TextField).first, r'$.items[*].n');
    expect(_editor(tester, 1).text, '[\n  "x",\n  "y"\n]');

    await tester.tap(find.text('Minify'));
    await tester.pumpAndSettle();
    expect(_editor(tester, 1).text, '["x","y"]');
  });

  testWidgets('JSON: tree view browses the document', (tester) async {
    await pumpApp(tester, location: '/tool/json');
    await tester.tap(find.text('Tree'));
    await tester.pumpAndSettle();
    expect(find.textContaining('"Super Toolbox"', findRichText: true), findsOneWidget);
    expect(find.textContaining('"authors"', findRichText: true), findsOneWidget);
  });

  testWidgets('JSON diff lists structural changes', (tester) async {
    await pumpApp(tester, location: '/tool/json_diff');
    expect(find.text(r'$.profile.city'), findsOneWidget);
    expect(find.text(r'$.active'), findsOneWidget);
    expect(find.textContaining('Type changed 1'), findsOneWidget);
    _editor(tester, 1).text = _editor(tester).text;
    await tester.pumpAndSettle();
    expect(find.text('The two documents are structurally identical'), findsOneWidget);
  });

  testWidgets('JSON to code switches languages', (tester) async {
    await pumpApp(tester, location: '/tool/json_code');
    expect(_editor(tester, 1).text, contains('export interface Root {'));
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(_editor(tester, 1).text, contains('type Root struct {'));
  });

  testWidgets('YAML round-trips through swap', (tester) async {
    await pumpApp(tester, location: '/tool/json_yaml');
    expect(_editor(tester, 1).text, contains('name: Super Toolbox'));
    await tester.tap(find.text('Swap'));
    await tester.pumpAndSettle();
    expect(find.text('YAML → JSON'), findsOneWidget);
    expect(_editor(tester, 1).text, contains('"name": "Super Toolbox"'));
  });

  testWidgets('JWT verifies the signature with the secret', (tester) async {
    await pumpApp(tester, location: '/tool/jwt');
    expect(find.text('Signature verified'), findsOneWidget);
    expect(_editor(tester, 1).text, contains('"name": "John Doe"'));
    await _type(tester, find.widgetWithText(TextField, 'your-256-bit-secret'), 'nope');
    expect(find.text('Invalid signature — wrong secret or tampered token'), findsOneWidget);
  });

  testWidgets('regex highlights matches and previews replacement', (tester) async {
    await pumpApp(tester, location: '/tool/regex');
    expect(find.text('2 match(es)'), findsOneWidget);
    await _type(tester, find.byType(TextField).first, r'(\d{4})-(\d{2})-(\d{2})');
    expect(find.text('1 match(es)'), findsOneWidget);
    expect(find.text(r'$1  2026'), findsOneWidget);
    await _type(tester, find.widgetWithText(TextField, r'<$0>'), r'$3/$2/$1');
    expect(find.textContaining('25/09/2026'), findsOneWidget);
    await _type(tester, find.byType(TextField).first, '(unclosed');
    expect(find.textContaining('Unterminated group'), findsOneWidget);
  });

  testWidgets('hash verifies an expected digest', (tester) async {
    await pumpApp(tester, location: '/tool/hash');
    await _type(tester, find.byType(TextField).first, 'abc');
    expect(find.text('900150983cd24fb0d6963f7d28e17f72'), findsOneWidget);
    await _type(
      tester,
      find.widgetWithText(TextField, 'Paste an expected hash to verify'),
      '900150983CD24FB0D6963F7D28E17F72',
    );
    expect(find.text('Matches MD5 ✓'), findsOneWidget);
  });

  testWidgets('Base64 encodes and decodes both ways', (tester) async {
    await pumpApp(tester, location: '/tool/base64');
    final fields = find.byType(TextField);
    await _type(tester, fields.first, 'hi 你好');
    expect(tester.widget<TextField>(fields.at(1)).controller!.text, 'aGkg5L2g5aW9');
    await _type(tester, fields.at(1), 'b2s=');
    expect(tester.widget<TextField>(fields.first).controller!.text, 'ok');
    await _type(tester, fields.at(1), '!!!');
    expect(find.textContaining('Invalid'), findsOneWidget);
  });

  testWidgets('encode tool switches codec and direction', (tester) async {
    await pumpApp(tester, location: '/tool/encode');
    final fields = find.byType(TextField);
    await _type(tester, fields.first, '<b>&</b>');
    await tester.tap(find.text('HTML Entity'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(fields.at(1)).controller!.text, '&lt;b&gt;&amp;&lt;/b&gt;');
    await tester.tap(find.text('Swap'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(fields.at(1)).controller!.text, '<b>&</b>');
  });

  testWidgets('text diff counts changes', (tester) async {
    await pumpApp(tester, location: '/tool/diff');
    expect(find.text('+1'), findsOneWidget);
    expect(find.text('~2'), findsOneWidget);
    _editor(tester, 1).text = _editor(tester).text;
    await tester.pumpAndSettle();
    expect(find.text('The texts are identical'), findsOneWidget);
  });

  testWidgets('timestamp parses what it is given', (tester) async {
    await pumpApp(tester, location: '/tool/timestamp');
    await _type(tester, find.byType(TextField), '1700000000000');
    expect(find.text('Unix milliseconds'), findsOneWidget);
    expect(find.text('Tue, 14 Nov 2023 22:13:20 GMT'), findsOneWidget);
    await _type(tester, find.byType(TextField), 'garbage');
    expect(find.textContaining('Not recognised'), findsOneWidget);
  });

  testWidgets('cron previews runs and rejects bad fields', (tester) async {
    await pumpApp(tester, location: '/tool/cron');
    expect(find.text('#12'), findsOneWidget);
    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    expect(find.text('0 0 1 * *'), findsOneWidget);
    await _type(tester, find.byType(TextField), '99 * * * *');
    expect(find.textContaining('Invalid value "99"'), findsOneWidget);
  });

  testWidgets('number base converts and flips bits', (tester) async {
    await pumpApp(tester, location: '/tool/number_base');
    expect(find.text('FF'), findsOneWidget);
    expect(find.text('1111 1111'), findsOneWidget);
    await _type(tester, find.byType(TextField), '0x1F4');
    expect(find.text('500'), findsOneWidget);
  });

  testWidgets('UUID generates the requested count', (tester) async {
    await pumpApp(tester, location: '/tool/uuid');
    expect(find.text('#10'), findsOneWidget);
    await tester.tap(find.text('50'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('#10'), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.text('#50'), findsOneWidget);
  });

  testWidgets('case converter shows every style', (tester) async {
    await pumpApp(tester, location: '/tool/case');
    await _type(tester, find.byType(TextField).first, 'hello big world');
    expect(find.text('helloBigWorld'), findsOneWidget);
    expect(find.text('HELLO_BIG_WORLD'), findsOneWidget);
    expect(find.text('hello-big-world'), findsOneWidget);
  });

  testWidgets('files handed to a tool are loaded (home drop)', (tester) async {
    await pumpApp(tester, location: '/tool/css');
    // Simulate a dropped .css file.
    final file = await tester.runAsync(() async {
      final f = (await Directory.systemTemp.createTemp('st')).path;
      final path = '$f/style.css';
      await File(path).writeAsString('a{color:red}');
      return path;
    });
    FileIntake.instance.offer('css', [file!]);
    // The page reads the file with real IO; let it complete step by step.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(_editor(tester).text, 'a{color:red}');
    expect(_editor(tester, 1).text, 'a {\n  color: red;\n}\n');
  });
}

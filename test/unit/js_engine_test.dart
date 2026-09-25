@TestOn('mac-os')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:super_ffmpeg/modules/web/engine/js_engine.dart';

void main() async {
  final skip = JsEngine.isAvailable ? null : 'JavaScriptCore unavailable';

  test('returns the completion value and captures console', () async {
    final r = await JsEngine.run('console.log("hi", 1+1, {a: [1, 2]}); const x = [3,1,2].sort(); x');
    expect(r.ok, isTrue, reason: r.error);
    expect(r.logs.single.text, 'hi 2 { a: [1, 2] }');
    expect(r.value, '[1, 2, 3]');
    expect(r.valueType, 'object');
  }, skip: skip);

  test('reports errors with line numbers', () async {
    final r = await JsEngine.run('let a = 1;\nnull.foo');
    expect(r.ok, isFalse);
    expect(r.error, contains('TypeError'));
    expect(r.error, contains('line 2'));
  }, skip: skip);

  test('runs timers on a virtual clock and promises', () async {
    final r = await JsEngine.run('''
      setTimeout(() => console.log("b"), 100);
      setTimeout(() => console.log("a"), 10);
      Promise.resolve(1).then(v => console.log("p", v));
      console.log("sync");
    ''');
    expect(r.logs.map((l) => l.text), ['sync', 'p 1', 'a', 'b']);
  }, skip: skip);

  test('stops infinite loops at the time limit', () async {
    final r = await JsEngine.run('while (true) {}', timeout: const Duration(milliseconds: 500));
    expect(r.timedOut, isTrue);
  }, skip: skip);

  test('keeps print() output and runs each script isolated', () async {
    final r = await JsEngine.run('print("raw"); globalThis.leak = 1; 1');
    expect(r.logs.first.text, 'raw');
    final r2 = await JsEngine.run('typeof leak');
    expect(r2.value, '"undefined"');
  }, skip: skip);

  test('warn level and numbers', () async {
    final r = await JsEngine.run('console.warn("w"); 40 + 2');
    expect(r.value, '42');
    expect(r.logs.single.level, 'warn');
  }, skip: skip);
}

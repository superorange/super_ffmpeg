import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// One `console.*` call captured while running a script.
@immutable
class JsLog {
  const JsLog(this.level, this.text);
  final String level;
  final String text;
}

@immutable
class JsResult {
  const JsResult({
    this.logs = const [],
    this.value,
    this.valueType,
    this.error,
    this.elapsed = Duration.zero,
    this.timedOut = false,
  });

  final List<JsLog> logs;

  /// Completion value of the script, formatted (null on error).
  final String? value;
  final String? valueType;
  final String? error;
  final Duration elapsed;
  final bool timedOut;

  bool get ok => error == null;
}

/// Runs JavaScript snippets with JavaScriptCore — the engine that ships with
/// macOS — through its `jsc` shell, so no browser or Node.js is needed.
///
/// Every run is a separate short-lived process (~15 ms startup): scripts are
/// fully isolated and an infinite loop is simply killed at the time limit.
/// `console.*`, timers (`setTimeout`/`setInterval` on a virtual clock) and
/// promises work.
abstract final class JsEngine {
  static const shellPath = '/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc';

  static bool get isAvailable => Platform.isMacOS && File(shellPath).existsSync();

  static Future<JsResult> run(String code, {Duration timeout = const Duration(seconds: 5)}) async {
    final dir = await Directory.systemTemp.createTemp('super_toolbox_js');
    final file = File('${dir.path}/main.js');
    await file.writeAsString(
      '$_prelude\nvar __src = ${jsonEncode(code)};\n__run();\n__flush();\n__drain();\nprint("$_markerJs" + __summary());\n',
    );
    final watch = Stopwatch()..start();
    try {
      final process = await Process.start(shellPath, [file.path]);
      final out = StringBuffer();
      final err = StringBuffer();
      final outDone = process.stdout.transform(utf8.decoder).forEach(out.write);
      final errDone = process.stderr.transform(utf8.decoder).forEach(err.write);
      final exit = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      await Future.wait([outDone, errDone]).timeout(const Duration(seconds: 1), onTimeout: () => const []);
      watch.stop();
      if (exit == -1) {
        return JsResult(error: 'Execution timed out after ${_secs(timeout)}', elapsed: watch.elapsed, timedOut: true);
      }
      return _parse(out.toString(), err.toString(), watch.elapsed);
    } finally {
      unawaited(dir.delete(recursive: true).catchError((_) => dir));
    }
  }

  static String _secs(Duration d) =>
      d.inMilliseconds % 1000 == 0 ? '${d.inSeconds}s' : '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';

  static JsResult _parse(String stdout, String stderr, Duration elapsed) {
    final i = stdout.lastIndexOf(_markerText);
    if (i < 0) {
      // The shell itself failed (syntax error in the wrapper, crash…).
      final message = stderr.trim().isEmpty ? stdout.trim() : stderr.trim();
      return JsResult(error: message.isEmpty ? 'JavaScript engine failed' : message, elapsed: elapsed);
    }
    final data = jsonDecode(stdout.substring(i + _markerText.length).trim()) as Map<String, dynamic>;
    // Anything the script printed with the shell's own print().
    final printed = stdout.substring(0, i).trimRight();
    final logs = [
      for (final line in printed.isEmpty ? const <String>[] : printed.split('\n')) JsLog('log', line),
      for (final l in (data['logs'] as List? ?? const [])) JsLog('${(l as List)[0]}', '${l[1]}'),
    ];
    return JsResult(
      logs: logs,
      value: data['value'] as String?,
      valueType: data['type'] as String?,
      error: data['error'] as String?,
      elapsed: elapsed,
    );
  }

  /// Separates script output from the result summary (escaped in JS).
  static const _markerJs = r'\u0001__super_toolbox__';
  static const _markerText = '\u0001__super_toolbox__';

  // Console capture, value formatting and a virtual-clock timer queue.
  static const _prelude = r'''
var __logs = [], __last, __ok = false, __err = null, __timers = [], __seq = 0, __clock = 0;
function __fmt(v, depth) {
  var seen = [];
  function inner(v, d) {
    var t = typeof v;
    if (t === 'string') return d > 0 ? JSON.stringify(v) : v;
    if (v === undefined) return 'undefined';
    if (v === null) return 'null';
    if (t === 'function') return '[Function: ' + (v.name || 'anonymous') + ']';
    if (t === 'bigint') return v.toString() + 'n';
    if (t === 'symbol') return v.toString();
    if (t !== 'object') return String(v);
    if (v instanceof Error) return v.name + ': ' + v.message;
    if (v instanceof Date) return v.toISOString();
    if (v instanceof RegExp) return String(v);
    if (seen.indexOf(v) >= 0) return '[Circular]';
    seen.push(v);
    var pad = '  '.repeat(d + 1), end = '  '.repeat(d);
    var out;
    if (v instanceof Map) {
      var es = []; v.forEach(function (val, k) { es.push(pad + inner(k, d + 1) + ' => ' + inner(val, d + 1)); });
      out = 'Map(' + v.size + ') {' + (es.length ? '\n' + es.join(',\n') + '\n' + end : '') + '}';
    } else if (v instanceof Set) {
      var ss = []; v.forEach(function (val) { ss.push(pad + inner(val, d + 1)); });
      out = 'Set(' + v.size + ') {' + (ss.length ? '\n' + ss.join(',\n') + '\n' + end : '') + '}';
    } else if (Array.isArray(v)) {
      var items = v.map(function (x) { return inner(x, d + 1); });
      var flat = '[' + items.join(', ') + ']';
      out = flat.length <= 72 && flat.indexOf('\n') < 0 ? flat : '[\n' + items.map(function (x) { return pad + x; }).join(',\n') + '\n' + end + ']';
    } else {
      var keys = Object.keys(v);
      var name = v.constructor && v.constructor.name && v.constructor.name !== 'Object' ? v.constructor.name + ' ' : '';
      var parts = keys.map(function (k) { return (/^[A-Za-z_$][\w$]*$/.test(k) ? k : JSON.stringify(k)) + ': ' + inner(v[k], d + 1); });
      var line = name + '{ ' + parts.join(', ') + ' }';
      out = keys.length === 0 ? name + '{}' : line.length <= 72 && line.indexOf('\n') < 0 ? line : name + '{\n' + parts.map(function (x) { return pad + x; }).join(',\n') + '\n' + end + '}';
    }
    seen.pop();
    return out;
  }
  return inner(v, depth);
}
var console = {};
['log', 'info', 'warn', 'error', 'debug'].forEach(function (level) {
  console[level] = function () {
    __logs.push([level, Array.prototype.map.call(arguments, function (a) { return __fmt(a, 0); }).join(' ')]);
  };
});
console.table = function (d) { __logs.push(['log', __fmt(d, 0)]); };
console.dir = console.log;
var __counts = {};
console.count = function (l) { l = l === undefined ? 'default' : l; __counts[l] = (__counts[l] || 0) + 1; __logs.push(['log', l + ': ' + __counts[l]]); };
var __times = {};
console.time = function (l) { __times[l === undefined ? 'default' : l] = Date.now(); };
console.timeEnd = function (l) { l = l === undefined ? 'default' : l; __logs.push(['log', l + ': ' + (Date.now() - (__times[l] || Date.now())) + 'ms']); };
function setTimeout(fn, ms) { var id = ++__seq; __timers.push({ id: id, fn: fn, at: __clock + (+ms || 0), args: Array.prototype.slice.call(arguments, 2) }); return id; }
function setInterval(fn, ms) { var id = ++__seq; __timers.push({ id: id, fn: fn, at: __clock + Math.max(1, +ms || 0), every: Math.max(1, +ms || 0), runs: 0, args: [] }); return id; }
function clearTimeout(id) { __timers = __timers.filter(function (t) { return t.id !== id; }); }
var clearInterval = clearTimeout;
function queueMicrotask(fn) { Promise.resolve().then(fn); }
function __run() {
  try { __last = (0, eval)(__src); __ok = true; }
  catch (e) {
    __err = (e && e.name ? e.name + ': ' + e.message : String(e)) + (e && e.line ? ' (line ' + e.line + (e.column ? ':' + e.column : '') + ')' : '');
  }
}
function __drain() {
  var guard = 0;
  while (__timers.length && guard++ < 10000) {
    __timers.sort(function (a, b) { return a.at - b.at || a.id - b.id; });
    var t = __timers.shift();
    __clock = t.at;
    if (t.every && ++t.runs < 1000) { t.at = __clock + t.every; __timers.push(t); }
    try { t.fn.apply(null, t.args); }
    catch (e) { __logs.push(['error', 'Uncaught ' + __fmt(e, 0)]); }
    __flush();
  }
}
function __flush() {
  try { if (typeof drainMicrotasks === 'function') drainMicrotasks(); }
  catch (e) { __logs.push(['error', 'Uncaught (in promise) ' + __fmt(e, 0)]); }
}
function __summary() {
  return JSON.stringify({ logs: __logs, value: __ok ? __fmt(__last, 1) : null, type: __ok ? typeof __last : null, error: __err });
}
''';
}

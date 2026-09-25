import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/toolbox/file_intake.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/buttons.dart';
import '../../../ui/widgets/code_area.dart';
import '../../../ui/widgets/editor_pane.dart';
import '../../../ui/widgets/workbench.dart';
import '../engine/js_engine.dart';
import '../web_module.dart';
import '../widgets/console_view.dart';

const jsSamples = <String, String>{
  'basics': '''// ⌘ Enter to run. The last expression is shown as the result.
const users = [
  { name: 'Alice', age: 30 },
  { name: 'Bob', age: 25 },
  { name: 'Carol', age: 41 },
];
console.log('Adults:', users.filter(u => u.age >= 30).map(u => u.name));
console.table(users);
users.reduce((sum, u) => sum + u.age, 0) / users.length''',
  'async': '''const sleep = (ms) => new Promise(r => setTimeout(r, ms));

async function main() {
  console.log('start');
  await sleep(500);
  console.log('after 500ms (virtual clock)');
  const results = await Promise.all([1, 2, 3].map(async n => n * n));
  console.log('squares', results);
}
main();''',
  'classes': '''class Stack {
  #items = [];
  push(x) { this.#items.push(x); return this; }
  pop() { return this.#items.pop(); }
  get size() { return this.#items.length; }
}
const s = new Stack().push(1).push(2).push(3);
console.log('popped', s.pop());
({ size: s.size, map: new Map([['a', 1]]), set: new Set([1, 2]) })''',
};

class JsPage extends StatefulWidget {
  const JsPage({super.key});

  @override
  State<JsPage> createState() => _JsPageState();
}

class _JsPageState extends State<JsPage> with FileIntakeMixin {
  @override
  String get intakeId => 'js_runner';

  @override
  void onFiles(List<String> paths) async {
    final text = await FileIntake.readText(paths.first);
    if (text != null) _code.text = text;
  }

  final _code = CodeLineEditingController.fromText(jsSamples['basics']);
  final _entries = <ConsoleEntry>[];
  JsResult? _last;
  bool _running = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() => _running = true);
    final r = await JsEngine.run(_code.text);
    if (!mounted) return;
    setState(() {
      _running = false;
      _last = r;
      _entries
        ..clear()
        ..addAll([for (final l in r.logs) ConsoleEntry(l.level, l.text)]);
      if (r.error != null) {
        _entries.add(ConsoleEntry('error', r.error!));
      } else if (r.value != null && r.valueType != 'undefined') {
        _entries.add(ConsoleEntry('log', r.value!, result: true));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final available = JsEngine.isAvailable;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _run,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _run,
      },
      child: ToolScaffold(
        tool: webTool('js_runner'),
        onFiles: onFiles,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'common.sample'.tr(),
            onSelected: (k) => _code.text = jsSamples[k]!,
            itemBuilder: (_) => [
              for (final k in jsSamples.keys) PopupMenuItem(value: k, child: Text('js_runner.sample_$k'.tr())),
            ],
            child: IgnorePointer(
              child: AppButton(
                label: 'common.sample'.tr(),
                icon: Icons.auto_awesome_outlined,
                size: ButtonSize.sm,
                onPressed: () {},
              ),
            ),
          ),
          AppButton.primary(
            label: 'js_runner.run'.tr(),
            icon: Icons.play_arrow_rounded,
            size: ButtonSize.sm,
            loading: _running,
            onPressed: available ? _run : null,
          ),
        ],
        body: SplitPane(
          initial: 0.55,
          first: EditorPane(
            title: 'JavaScript',
            controller: _code,
            language: CodeLang.javascript,
            open: true,
            save: true,
            saveName: 'script.js',
            openExtensions: const ['js', 'mjs', 'txt'],
            footer: StatusLine('js_runner.hint'.tr()),
          ),
          second: Pane(
            title: 'html_preview.console'.tr(),
            icon: Icons.terminal_rounded,
            color: c.codeBg,
            actions: [
              CopyAction(text: () => _entries.map((e) => e.text).join('\n')),
              PaneAction(
                icon: Icons.block_rounded,
                tooltip: 'common.clear'.tr(),
                onPressed: () => setState(_entries.clear),
              ),
            ],
            footer: _last == null
                ? StatusLine(available ? 'js_runner.engine'.tr() : 'js_runner.unavailable'.tr())
                : StatusLine(
                    '${_last!.ok ? 'js_runner.done'.tr() : (_last!.timedOut ? 'js_runner.timeout'.tr() : 'js_runner.failed'.tr())}'
                    '  ·  ${_last!.elapsed.inMilliseconds} ms',
                    tone: _last!.ok ? StatusTone.success : StatusTone.danger,
                  ),
            child: ConsoleView(
              entries: _entries,
              empty: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_circle_outline_rounded, size: 30, color: c.textSubtle),
                    const SizedBox(height: 8),
                    Text('js_runner.empty'.tr(), style: TextStyles.body.copyWith(color: c.textSubtle)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/toolbox/file_intake.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/buttons.dart';
import '../../../ui/widgets/code_area.dart';
import '../../../ui/widgets/feedback.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/web_preview.dart';
import '../../../ui/widgets/workbench.dart';
import '../web_module.dart';
import '../widgets/console_view.dart';

enum _Tab { html, css, js }

const _html = '''<main class="card">
  <h1>Hello, Super Toolbox 👋</h1>
  <p>Edit HTML, CSS and JavaScript — the preview updates as you type.</p>
  <button id="btn">Click me</button>
  <p class="count">Clicked <b id="n">0</b> times</p>
</main>''';

const _css = '''body {
  margin: 0;
  min-height: 100vh;
  display: grid;
  place-items: center;
  font-family: -apple-system, system-ui, sans-serif;
  background: linear-gradient(135deg, #7c6cff, #c06cff);
}
.card {
  background: white;
  padding: 32px 40px;
  border-radius: 20px;
  box-shadow: 0 20px 60px rgba(0, 0, 0, .25);
  text-align: center;
}
button {
  border: 0;
  padding: 10px 22px;
  border-radius: 10px;
  background: #7c6cff;
  color: white;
  font-size: 15px;
  cursor: pointer;
}''';

const _js = '''let n = 0;
document.getElementById('btn').addEventListener('click', () => {
  n++;
  document.getElementById('n').textContent = n;
  console.log('clicked', n);
});
console.info('Ready at', new Date().toLocaleTimeString());''';

/// HTML + CSS + JS playground with a live WebKit preview and console.
class HtmlPage extends StatefulWidget {
  const HtmlPage({super.key});

  @override
  State<HtmlPage> createState() => _HtmlPageState();
}

class _HtmlPageState extends State<HtmlPage> with FileIntakeMixin {
  @override
  String get intakeId => 'html_preview';

  @override
  void onFiles(List<String> paths) async {
    for (final path in paths) {
      final text = await FileIntake.readText(path);
      if (text == null) continue;
      final lower = path.toLowerCase();
      final tab = lower.endsWith('.css') ? _Tab.css : (lower.endsWith('.js') ? _Tab.js : _Tab.html);
      _editors[tab]!.text = text;
      setState(() => _tab = tab);
    }
    _refresh();
  }

  final _editors = {
    _Tab.html: CodeLineEditingController.fromText(_html),
    _Tab.css: CodeLineEditingController.fromText(_css),
    _Tab.js: CodeLineEditingController.fromText(_js),
  };
  var _tab = _Tab.html;
  var _auto = true;
  var _document = '';
  var _run = 0;
  final _console = <ConsoleEntry>[];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    for (final e in _editors.values) {
      e.addListener(outsideBuild(_changed));
    }
    _document = _compose();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final e in _editors.values) {
      e.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (!_auto) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _refresh);
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _console.clear();
      _run++;
      _document = _compose();
    });
  }

  String _compose() {
    final html = _editors[_Tab.html]!.text;
    final css = _editors[_Tab.css]!.text;
    final js = _editors[_Tab.js]!.text;
    // A full document in the HTML tab is used as-is (CSS/JS appended).
    if (RegExp(r'<html[\s>]', caseSensitive: false).hasMatch(html)) {
      return html
          .replaceFirst(RegExp(r'</head>', caseSensitive: false), '<style>$css</style></head>')
          .replaceFirst(RegExp(r'</body>', caseSensitive: false), '<script>$js</script></body>');
    }
    return '<!doctype html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<style>$css</style></head><body>$html<script>\n$js\n</script>'
        '<!-- run $_run --></body></html>';
  }

  Future<void> _export() async {
    final path = await FilePicker.platform.saveFile(fileName: 'index.html');
    if (path == null) return;
    await File(path).writeAsString(_compose());
    if (mounted) showToast(context, 'common.saved'.tr(namedArgs: {'path': path}));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final editor = Pane(
      color: c.codeBg,
      headerExtra: Segmented<_Tab>(
        expand: false,
        dense: true,
        value: _tab,
        onChanged: (v) => setState(() => _tab = v),
        items: const [ChoiceItem(_Tab.html, 'HTML'), ChoiceItem(_Tab.css, 'CSS'), ChoiceItem(_Tab.js, 'JavaScript')],
      ),
      actions: [
        CopyAction(text: () => _editors[_tab]!.text),
        PaneAction(
          icon: Icons.backspace_outlined,
          tooltip: 'common.clear'.tr(),
          onPressed: () => _editors[_tab]!.text = '',
        ),
      ],
      child: IndexedStack(
        index: _tab.index,
        children: [
          CodeArea(controller: _editors[_Tab.html]!, language: CodeLang.html),
          CodeArea(controller: _editors[_Tab.css]!, language: CodeLang.css),
          CodeArea(controller: _editors[_Tab.js]!, language: CodeLang.javascript),
        ],
      ),
    );

    final preview = SplitPane(
      vertical: true,
      initial: 0.72,
      minExtent: 80,
      first: Pane(
        title: 'html_preview.preview'.tr(),
        icon: Icons.visibility_outlined,
        actions: [
          PaneAction(icon: Icons.refresh_rounded, tooltip: 'html_preview.run'.tr(), onPressed: _refresh),
        ],
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(Radii.card)),
          child: WebPreview(
            html: _document,
            onConsole: (level, text) {
              if (mounted) setState(() => _console.add(ConsoleEntry(level, text)));
            },
          ),
        ),
      ),
      second: Pane(
        title: 'html_preview.console'.tr(),
        icon: Icons.terminal_rounded,
        color: c.codeBg,
        actions: [
          PaneAction(
            icon: Icons.block_rounded,
            tooltip: 'common.clear'.tr(),
            onPressed: () => setState(_console.clear),
          ),
        ],
        child: ConsoleView(
          entries: _console,
          empty: Center(
            child: Text('html_preview.console_empty'.tr(), style: TextStyles.caption.copyWith(color: c.textSubtle)),
          ),
        ),
      ),
    );

    return ToolScaffold(
      tool: webTool('html_preview'),
      onFiles: onFiles,
      actions: [
        ToolbarField(
          label: 'html_preview.auto'.tr(),
          child: AppSwitch(value: _auto, onChanged: (v) => setState(() => _auto = v)),
        ),
        AppButton(
          label: 'common.export_html'.tr(),
          icon: Icons.ios_share_rounded,
          size: ButtonSize.sm,
          onPressed: _export,
        ),
        AppButton.primary(
          label: 'html_preview.run'.tr(),
          icon: Icons.play_arrow_rounded,
          size: ButtonSize.sm,
          onPressed: _refresh,
        ),
      ],
      body: SplitPane(initial: 0.46, first: editor, second: preview),
    );
  }
}

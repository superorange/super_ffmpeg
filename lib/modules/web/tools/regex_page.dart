import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/workbench.dart';
import '../web_module.dart';

const _samples = <String, String>{
  'Email': r'[\w.+-]+@[\w-]+\.[\w.-]+',
  'URL': r'https?://[^\s/$.?#].[^\s]*',
  'IPv4': r'\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b',
  '手机号': r'\b1[3-9]\d{9}\b',
  '日期': r'(\d{4})-(\d{2})-(\d{2})',
  'Hex': r'#(?:[0-9a-fA-F]{3}){1,2}\b',
  '中文': r'[一-龥]+',
};

const _text = '''Contact: alice@example.com, bob.smith+dev@mail.co.uk
Visit https://example.com/docs?q=regex or http://localhost:8080
Server 192.168.1.20 · backup 10.0.0.256 (invalid)
手机 13812345678 · 日期 2026-09-25 · 颜色 #7c6cff #fff''';

/// Highlights regex matches directly inside the test text.
class _MatchController extends TextEditingController {
  _MatchController(String text) : super(text: text);
  List<RegExpMatch> matches = const [];
  Color highlight = Colors.transparent;
  Color highlightAlt = Colors.transparent;

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (matches.isEmpty) return TextSpan(text: text, style: style);
    final spans = <TextSpan>[];
    var pos = 0;
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      if (m.start > text.length || m.end > text.length) break;
      if (m.start > pos) spans.add(TextSpan(text: text.substring(pos, m.start)));
      if (m.end > m.start) {
        spans.add(
          TextSpan(
            text: text.substring(m.start, m.end),
            style: TextStyle(backgroundColor: i.isEven ? highlight : highlightAlt),
          ),
        );
      }
      pos = m.end;
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
    return TextSpan(style: style, children: spans);
  }
}

class RegexPage extends StatefulWidget {
  const RegexPage({super.key});

  @override
  State<RegexPage> createState() => _RegexPageState();
}

class _RegexPageState extends State<RegexPage> {
  final _pattern = TextEditingController(text: _samples['Email']);
  final _replace = TextEditingController(text: r'<$0>');
  final _test = _MatchController(_text);
  var _ignoreCase = false, _multiLine = true, _dotAll = false, _unicode = true;
  RegExp? _re;
  String? _error;
  List<RegExpMatch> _matches = const [];

  @override
  void initState() {
    super.initState();
    _pattern.addListener(_run);
    _test.addListener(_run);
    _replace.addListener(() => setState(() {}));
    _run();
  }

  @override
  void dispose() {
    _pattern.dispose();
    _replace.dispose();
    _test.dispose();
    super.dispose();
  }

  void _run() {
    _error = null;
    _re = null;
    _matches = const [];
    if (_pattern.text.isNotEmpty) {
      try {
        _re = RegExp(
          _pattern.text,
          caseSensitive: !_ignoreCase,
          multiLine: _multiLine,
          dotAll: _dotAll,
          unicode: _unicode,
        );
        _matches = _re!.allMatches(_test.text).take(5000).toList();
      } on FormatException catch (e) {
        _error = e.message;
      }
    }
    _test.matches = _matches;
    if (mounted) setState(() {});
  }

  String _replaced() {
    if (_re == null) return _test.text;
    return _test.text.replaceAllMapped(_re!, (match) {
      final m = match as RegExpMatch;
      return _replace.text.replaceAllMapped(RegExp(r'\$(\d+|&|\$)|\$<(\w+)>'), (r) {
        if (r[1] == r'$') return r'$';
        if (r[1] == '&' || r[1] == '0') return m[0]!;
        if (r[2] != null) {
          try {
            return m.namedGroup(r[2]!) ?? '';
          } catch (_) {
            return '';
          }
        }
        final i = int.parse(r[1]!);
        return i <= m.groupCount ? (m[i] ?? '') : r[0]!;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    _test
      ..highlight = c.accent.withValues(alpha: 0.32)
      ..highlightAlt = c.warning.withValues(alpha: 0.32);

    Widget flag(String label, String hint, bool v, ValueChanged<bool> f) => SelectableChip(
      label: label,
      tooltip: hint,
      selected: v,
      onTap: () {
        f(!v);
        _run();
      },
    );

    final patternBar = Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: _error != null ? c.danger : c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('/', style: TextStyles.mono.copyWith(fontSize: 18, color: c.textSubtle)),
              Expanded(
                child: TextField(
                  controller: _pattern,
                  style: TextStyles.mono.copyWith(fontSize: 15, color: c.text),
                  decoration: InputDecoration(
                    hintText: 'regex.pattern_hint'.tr(),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              Text(
                '/${_ignoreCase ? 'i' : ''}${_multiLine ? 'm' : ''}${_dotAll ? 's' : ''}${_unicode ? 'u' : ''}g',
                style: TextStyles.mono.copyWith(fontSize: 18, color: c.textSubtle),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Wrap(
                spacing: 6,
                children: [
                  flag('i', 'regex.flag_i'.tr(), _ignoreCase, (v) => _ignoreCase = v),
                  flag('m', 'regex.flag_m'.tr(), _multiLine, (v) => _multiLine = v),
                  flag('s', 'regex.flag_s'.tr(), _dotAll, (v) => _dotAll = v),
                  flag('u', 'regex.flag_u'.tr(), _unicode, (v) => _unicode = v),
                ],
              ),
              const SizedBox(width: Space.lg),
              Expanded(
                child: _error != null
                    ? StatusLine(_error!, tone: StatusTone.danger)
                    : StatusLine(
                        'regex.matches'.tr(namedArgs: {'n': '${_matches.length}'}),
                        tone: _matches.isEmpty ? StatusTone.neutral : StatusTone.success,
                      ),
              ),
              PopupMenuButton<String>(
                tooltip: 'regex.library'.tr(),
                onSelected: (k) => _pattern.text = _samples[k]!,
                itemBuilder: (_) => [
                  for (final e in _samples.entries)
                    PopupMenuItem(
                      value: e.key,
                      child: Row(
                        children: [
                          SizedBox(width: 64, child: Text(e.key)),
                          Text(e.value, style: TextStyles.mono.copyWith(fontSize: 11, color: c.textSubtle)),
                        ],
                      ),
                    ),
                ],
                child: Row(
                  children: [
                    Icon(Icons.library_books_outlined, size: 15, color: c.accent),
                    const SizedBox(width: 4),
                    Text('regex.library'.tr(), style: TextStyles.label.copyWith(color: c.accent)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final testPane = Pane(
      title: 'regex.test_text'.tr(),
      icon: Icons.text_snippet_outlined,
      color: c.codeBg,
      actions: [
        PaneAction(
          icon: Icons.content_paste_rounded,
          tooltip: 'common.paste'.tr(),
          onPressed: () async {
            final t = await readClipboard();
            if (t != null) _test.text = t;
          },
        ),
        PaneAction(icon: Icons.backspace_outlined, tooltip: 'common.clear'.tr(), onPressed: _test.clear),
      ],
      child: TextArea(controller: _test),
    );

    final matchesPane = Pane(
      title: 'regex.match_list'.tr(),
      icon: Icons.format_list_numbered_rounded,
      actions: [CopyAction(text: () => _matches.map((m) => m[0]).join('\n'))],
      child: ListView.builder(
        padding: const EdgeInsets.all(6),
        itemCount: _matches.length,
        itemBuilder: (_, i) {
          final m = _matches[i];
          final names = m.groupNames.toList();
          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: c.surfaceAlt.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(Radii.control),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('#${i + 1}', style: TextStyles.caption.copyWith(color: c.textSubtle)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectableText(m[0]!, style: TextStyles.mono.copyWith(fontSize: 12, color: c.text)),
                    ),
                    Text('${m.start}–${m.end}', style: TextStyles.caption.copyWith(color: c.textSubtle)),
                  ],
                ),
                for (var g = 1; g <= m.groupCount; g++)
                  Padding(
                    padding: const EdgeInsets.only(left: 22, top: 2),
                    child: Text(
                      '\$$g  ${m[g] ?? '∅'}',
                      style: TextStyles.mono.copyWith(fontSize: 11.5, color: c.textMuted),
                    ),
                  ),
                for (final n in names)
                  Padding(
                    padding: const EdgeInsets.only(left: 22, top: 2),
                    child: Text(
                      '<$n>  ${m.namedGroup(n) ?? '∅'}',
                      style: TextStyles.mono.copyWith(fontSize: 11.5, color: c.info),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );

    final replacePane = Pane(
      title: 'regex.replace'.tr(),
      icon: Icons.find_replace_rounded,
      actions: [CopyAction(text: _replaced)],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: TextField(
              controller: _replace,
              style: TextStyles.mono.copyWith(fontSize: 12.5, color: c.text),
              decoration: InputDecoration(hintText: r'$1 · $<name> · $&'),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(_replaced(), style: TextStyles.mono.copyWith(color: c.text)),
            ),
          ),
        ],
      ),
    );

    return ToolScaffold(
      tool: webTool('regex'),
      toolbar: patternBar,
      body: SplitPane(
        initial: 0.55,
        first: testPane,
        second: SplitPane(vertical: true, first: matchesPane, second: replacePane),
      ),
    );
  }
}

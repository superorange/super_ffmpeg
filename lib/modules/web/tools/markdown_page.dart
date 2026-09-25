import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/toolbox/file_intake.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/buttons.dart';
import '../../../ui/widgets/code_area.dart';
import '../../../ui/widgets/editor_pane.dart';
import '../../../ui/widgets/feedback.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/web_preview.dart';
import '../../../ui/widgets/workbench.dart';
import '../../text/logic/text_tools.dart';
import '../logic/markdown_render.dart';
import '../web_module.dart';

const markdownSample = '''# Super Toolbox Markdown

Write on the left, see it rendered on the right. **Bold**, *italic*, ~~strike~~, `code` and [links](https://example.com).

## Lists

- [x] Live preview
- [x] GitHub-flavoured tables & task lists
- [ ] Your next great idea

1. First
2. Second

## Code

```js
const greet = (name) => `Hello, \${name}!`;
console.log(greet('world'));
```

## Table

| Tool | Category | Local |
| :--- | :------: | ----: |
| JSON | Data     |    ✅ |
| GIF  | Media    |    ✅ |

> Everything runs on your machine — nothing is uploaded.
''';

enum _View { edit, split, preview }

class MarkdownPage extends StatefulWidget {
  const MarkdownPage({super.key});

  @override
  State<MarkdownPage> createState() => _MarkdownPageState();
}

class _MarkdownPageState extends State<MarkdownPage> with FileIntakeMixin {
  @override
  String get intakeId => 'markdown';

  @override
  void onFiles(List<String> paths) async {
    final text = await FileIntake.readText(paths.first);
    if (text == null) return;
    _editor.text = text;
    setState(() => _path = paths.first);
  }

  final _editor = CodeLineEditingController.fromText(markdownSample);
  var _view = _View.split;
  var _rendered = markdownSample;
  String? _path;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _editor.addListener(
      outsideBuild(() {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 250), () {
          if (mounted) setState(() => _rendered = _editor.text);
        });
      }),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _editor.dispose();
    super.dispose();
  }

  void _wrap(String before, [String? after]) {
    final sel = _editor.selectedText;
    _editor.replaceSelection('$before${sel.isEmpty ? 'text' : sel}${after ?? before}');
  }

  void _linePrefix(String prefix) {
    final sel = _editor.selectedText;
    if (sel.isEmpty) {
      _editor.moveCursorToLineStart();
      _editor.replaceSelection(prefix);
    } else {
      _editor.replaceSelection(sel.split('\n').map((l) => '$prefix$l').join('\n'));
    }
  }

  void _insert(String block) => _editor.replaceSelection(block);

  Future<void> _open() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['md', 'markdown', 'txt']);
    final path = r?.files.single.path;
    if (path == null) return;
    _editor.text = await File(path).readAsString();
    setState(() => _path = path);
  }

  Future<void> _save({bool html = false}) async {
    final base = _path == null ? 'document' : _path!.split('/').last.replaceAll(RegExp(r'\.\w+$'), '');
    final path = await FilePicker.platform.saveFile(fileName: html ? '$base.html' : '$base.md');
    if (path == null) return;
    await File(path).writeAsString(
      html ? MarkdownRender.page(_editor.text, dark: false, title: base) : _editor.text,
    );
    if (!html) setState(() => _path = path);
    if (mounted) showToast(context, 'common.saved'.tr(namedArgs: {'path': path}));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final stats = TextTools.stats(_rendered);
    final tools = <(IconData, String, VoidCallback)>[
      (Icons.title_rounded, 'markdown.heading', () => _linePrefix('## ')),
      (Icons.format_bold_rounded, 'markdown.bold', () => _wrap('**')),
      (Icons.format_italic_rounded, 'markdown.italic', () => _wrap('*')),
      (Icons.strikethrough_s_rounded, 'markdown.strike', () => _wrap('~~')),
      (Icons.code_rounded, 'markdown.code', () => _wrap('`')),
      (Icons.link_rounded, 'markdown.link', () => _wrap('[', '](https://)')),
      (Icons.image_outlined, 'markdown.image', () => _wrap('![', '](https://)')),
      (Icons.format_list_bulleted_rounded, 'markdown.list', () => _linePrefix('- ')),
      (Icons.format_list_numbered_rounded, 'markdown.numbered', () => _linePrefix('1. ')),
      (Icons.checklist_rounded, 'markdown.task', () => _linePrefix('- [ ] ')),
      (Icons.format_quote_rounded, 'markdown.quote', () => _linePrefix('> ')),
      (Icons.data_array_rounded, 'markdown.code_block', () => _wrap('```\n', '\n```')),
      (Icons.table_chart_outlined, 'markdown.table', () => _insert('\n| A | B |\n| --- | --- |\n| 1 | 2 |\n')),
      (Icons.horizontal_rule_rounded, 'markdown.hr', () => _insert('\n---\n')),
    ];

    final editor = EditorPane(
      title: _path?.split('/').last ?? 'Markdown',
      icon: Icons.edit_note_rounded,
      controller: _editor,
      language: CodeLang.markdown,
      wordWrap: true,
      paste: false,
      footer: StatusLine(
        'markdown.stats'.tr(
          namedArgs: {
            'words': '${stats.words}',
            'chars': '${stats.characters}',
            'min': '${(stats.readingTime.inSeconds / 60).ceil()}',
          },
        ),
      ),
    );
    final preview = Pane(
      title: 'html_preview.preview'.tr(),
      icon: Icons.visibility_outlined,
      actions: [CopyAction(text: () => MarkdownRender.body(_editor.text))],
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(Radii.card)),
        child: WebPreview(
          html: MarkdownRender.page(_rendered, dark: c.isDark),
          baseUrl: _path == null ? null : 'file://${File(_path!).parent.path}/',
        ),
      ),
    );

    return ToolScaffold(
      tool: webTool('markdown'),
      onFiles: onFiles,
      actions: [
        AppButton(
          label: 'common.open_file'.tr(),
          icon: Icons.file_open_outlined,
          size: ButtonSize.sm,
          onPressed: _open,
        ),
        AppButton(label: 'common.save'.tr(), icon: Icons.save_alt_rounded, size: ButtonSize.sm, onPressed: _save),
        AppButton(
          label: 'common.export_html'.tr(),
          icon: Icons.ios_share_rounded,
          size: ButtonSize.sm,
          onPressed: () => _save(html: true),
        ),
      ],
      toolbar: ToolbarRow(
        trailing: Segmented<_View>(
          expand: false,
          value: _view,
          onChanged: (v) => setState(() => _view = v),
          items: [
            ChoiceItem(_View.edit, 'markdown.edit'.tr(), icon: Icons.edit_outlined),
            ChoiceItem(_View.split, 'markdown.split'.tr(), icon: Icons.vertical_split_outlined),
            ChoiceItem(_View.preview, 'html_preview.preview'.tr(), icon: Icons.visibility_outlined),
          ],
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(Radii.control),
              border: Border.all(color: c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [for (final (icon, key, f) in tools) PaneAction(icon: icon, tooltip: key.tr(), onPressed: f)],
            ),
          ),
        ],
      ),
      body: switch (_view) {
        _View.edit => editor,
        _View.preview => preview,
        _View.split => SplitPane(first: editor, second: preview),
      },
    );
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/workbench.dart';
import '../logic/text_tools.dart';
import '../text_module.dart';

/// Word/character counts plus one-click line operations with undo.
class TextToolsPage extends StatefulWidget {
  const TextToolsPage({super.key});

  @override
  State<TextToolsPage> createState() => _TextToolsPageState();
}

class _TextToolsPageState extends State<TextToolsPage> {
  final _text = TextEditingController(
    text: 'banana\napple\nCherry\napple\n\n  date  \nfig10\nfig2\n这是一段中文，用来统计字数。',
  );
  final _history = <String>[];

  static const _ops = <(LineOp, IconData)>[
    (LineOp.sortAsc, Icons.sort_by_alpha_rounded),
    (LineOp.sortDesc, Icons.sort_rounded),
    (LineOp.sortNatural, Icons.format_list_numbered_rounded),
    (LineOp.sortLength, Icons.straighten_rounded),
    (LineOp.reverse, Icons.swap_vert_rounded),
    (LineOp.unique, Icons.filter_1_rounded),
    (LineOp.removeEmpty, Icons.remove_road_rounded),
    (LineOp.trim, Icons.format_indent_decrease_rounded),
    (LineOp.collapseSpaces, Icons.space_bar_rounded),
    (LineOp.number, Icons.pin_outlined),
    (LineOp.joinLines, Icons.wrap_text_rounded),
    (LineOp.shuffle, Icons.shuffle_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _apply(LineOp op) {
    _history.add(_text.text);
    _text.text = TextTools.applyLineOp(_text.text, op);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = TextTools.stats(_text.text);
    final stats = [
      ('text_tools.characters'.tr(), '${s.characters}'),
      ('text_tools.no_spaces'.tr(), '${s.charactersNoSpaces}'),
      ('text_tools.words'.tr(), '${s.words}'),
      ('text_tools.lines'.tr(), '${s.lines}'),
      ('text_tools.paragraphs'.tr(), '${s.paragraphs}'),
      ('text_tools.bytes'.tr(), Fmt.bytes(s.bytes)),
      (
        'text_tools.reading'.tr(),
        s.readingTime.inSeconds < 60 ? '${s.readingTime.inSeconds}s' : '${(s.readingTime.inSeconds / 60).ceil()} min',
      ),
    ];

    return ToolScaffold(
      tool: textTool('text_tools'),
      toolbar: LayoutBuilder(
        builder: (context, box) {
          final cols = (box.maxWidth / 130).floor().clamp(3, stats.length);
          final w = (box.maxWidth - 10 * (cols - 1)) / cols;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (k, v) in stats)
                Container(
                  width: w,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(Radii.card),
                    border: Border.all(color: c.border),
                    boxShadow: c.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        v,
                        style: TextStyles.title.copyWith(
                          color: c.text,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(k, style: TextStyles.caption.copyWith(color: c.textSubtle)),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
      body: Pane(
        title: 'common.input'.tr(),
        headerExtra: Wrap(
          spacing: 2,
          children: [
            for (final (op, icon) in _ops)
              PaneAction(icon: icon, tooltip: 'text_tools.ops.${op.name}'.tr(), onPressed: () => _apply(op)),
          ],
        ),
        actions: [
          PaneAction(
            icon: Icons.undo_rounded,
            tooltip: 'common.undo'.tr(),
            onPressed: _history.isEmpty ? null : () => _text.text = _history.removeLast(),
          ),
          PaneAction(
            icon: Icons.content_paste_rounded,
            tooltip: 'common.paste'.tr(),
            onPressed: () async => _text.text = await readClipboard() ?? _text.text,
          ),
          CopyAction(text: () => _text.text),
          PaneAction(icon: Icons.backspace_outlined, tooltip: 'common.clear'.tr(), onPressed: _text.clear),
        ],
        child: TextArea(controller: _text),
      ),
    );
  }
}

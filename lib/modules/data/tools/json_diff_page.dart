import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/toolbox/file_intake.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/buttons.dart';
import '../../../ui/widgets/code_area.dart';
import '../../../ui/widgets/editor_pane.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/workbench.dart';
import '../../text/logic/diff.dart';
import '../../text/widgets/diff_view.dart';
import '../data_module.dart';
import '../logic/json_tools.dart';

const _left =
    '{\n  "id": 1,\n  "name": "Alice",\n  "roles": ["admin", "dev"],\n  "profile": { "city": "Shanghai", "age": 30 }\n}';
const _right =
    '{\n  "name": "Alice",\n  "id": 1,\n  "roles": ["admin", "ops", "dev"],\n  "profile": { "city": "Hangzhou", "age": "30" },\n  "active": true\n}';

class JsonDiffPage extends StatefulWidget {
  const JsonDiffPage({super.key});

  @override
  State<JsonDiffPage> createState() => _JsonDiffPageState();
}

class _JsonDiffPageState extends State<JsonDiffPage> with FileIntakeMixin {
  @override
  String get intakeId => 'json_diff';

  @override
  void onFiles(List<String> paths) async {
    final texts = [for (final p in paths.take(2)) await FileIntake.readText(p)];
    if (texts.length == 2) {
      if (texts[0] != null) _a.text = texts[0]!;
      if (texts[1] != null) _b.text = texts[1]!;
    } else if (texts.single != null) {
      (_a.text == _left ? _a : _b).text = texts.single!;
    }
  }

  final _a = CodeLineEditingController.fromText(_left);
  final _b = CodeLineEditingController.fromText(_right);
  var _textView = false;
  JsonParse? _pa;
  JsonParse? _pb;
  List<JsonChange> _changes = const [];
  TextDiffResult? _text;

  @override
  void initState() {
    super.initState();
    _a.addListener(outsideBuild(_run));
    _b.addListener(outsideBuild(_run));
    _run();
  }

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _run() {
    _pa = JsonTools.parse(_a.text);
    _pb = JsonTools.parse(_b.text);
    if (_pa!.ok && _pb!.ok) {
      _changes = jsonDiff(_pa!.value, _pb!.value);
      _text = diffLines(
        JsonTools.format(_pa!.value, sortKeys: true),
        JsonTools.format(_pb!.value, sortKeys: true),
      );
    } else {
      _changes = const [];
      _text = null;
    }
    if (mounted) setState(() {});
  }

  Widget _status(JsonParse? p) => p == null || p.ok
      ? StatusLine('json.valid_short'.tr(), tone: StatusTone.success)
      : StatusLine(p.error.toString(), tone: StatusTone.danger);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ready = _pa?.ok == true && _pb?.ok == true;
    final counts = {for (final k in JsonChangeKind.values) k: _changes.where((x) => x.kind == k).length};

    final results = Pane(
      title: 'json_diff.result'.tr(),
      headerExtra: Segmented<bool>(
        expand: false,
        dense: true,
        value: _textView,
        onChanged: (v) => setState(() => _textView = v),
        items: [
          ChoiceItem(false, 'json_diff.structural'.tr(), icon: Icons.list_alt_rounded),
          ChoiceItem(true, 'json_diff.side_by_side'.tr(), icon: Icons.vertical_split_outlined),
        ],
      ),
      actions: [
        if (ready)
          CopyAction(
            text: () => _changes
                .map((ch) => '${ch.kind.name.toUpperCase()} ${ch.path}: ${_short(ch.before)} → ${_short(ch.after)}')
                .join('\n'),
          ),
      ],
      footer: ready
          ? Row(
              children: [
                _Count(color: c.success, label: 'json_diff.added'.tr(), n: counts[JsonChangeKind.added]!),
                _Count(color: c.danger, label: 'json_diff.removed'.tr(), n: counts[JsonChangeKind.removed]!),
                _Count(color: c.warning, label: 'json_diff.changed'.tr(), n: counts[JsonChangeKind.changed]!),
                _Count(color: c.info, label: 'json_diff.type_changed'.tr(), n: counts[JsonChangeKind.typeChanged]!),
                const Spacer(),
                Text('json_diff.key_order_ignored'.tr(), style: TextStyles.caption.copyWith(color: c.textSubtle)),
              ],
            )
          : null,
      child: !ready
          ? Center(
              child: Text('json_diff.fix_input'.tr(), style: TextStyles.body.copyWith(color: c.textSubtle)),
            )
          : _changes.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, color: c.success, size: 32),
                  const SizedBox(height: 8),
                  Text('json_diff.identical'.tr(), style: TextStyles.heading.copyWith(color: c.text)),
                ],
              ),
            )
          : _textView
          ? DiffView(result: _text!)
          : ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: _changes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (_, i) => _ChangeRow(change: _changes[i]),
            ),
    );

    return ToolScaffold(
      tool: dataTool('json_diff'),
      onFiles: onFiles,
      actions: [
        AppButton(
          label: 'common.swap'.tr(),
          icon: Icons.swap_horiz_rounded,
          size: ButtonSize.sm,
          onPressed: () {
            final t = _a.text;
            _a.text = _b.text;
            _b.text = t;
          },
        ),
      ],
      body: SplitPane(
        vertical: true,
        initial: 0.45,
        minExtent: 140,
        first: SplitPane(
          first: EditorPane(
            title: 'json_diff.left'.tr(),
            controller: _a,
            language: CodeLang.json,
            open: true,
            footer: _status(_pa),
          ),
          second: EditorPane(
            title: 'json_diff.right'.tr(),
            controller: _b,
            language: CodeLang.json,
            open: true,
            footer: _status(_pb),
          ),
        ),
        second: results,
      ),
    );
  }

  static String _short(Object? v) {
    final s = jsonEncode(v);
    return s.length > 60 ? '${s.substring(0, 57)}…' : s;
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.color, required this.label, required this.n});
  final Color color;
  final String label;
  final int n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text('$label $n', style: TextStyles.caption.copyWith(color: context.colors.textMuted)),
        ],
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.change});
  final JsonChange change;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (color, label) = switch (change.kind) {
      JsonChangeKind.added => (c.success, 'json_diff.added'.tr()),
      JsonChangeKind.removed => (c.danger, 'json_diff.removed'.tr()),
      JsonChangeKind.changed => (c.warning, 'json_diff.changed'.tr()),
      JsonChangeKind.typeChanged => (c.info, 'json_diff.type_changed'.tr()),
    };
    final mono = TextStyles.mono.copyWith(fontSize: 12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 2,
            child: SelectableText(change.path, style: mono.copyWith(color: c.text)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text.rich(
              TextSpan(
                children: [
                  if (change.kind != JsonChangeKind.added)
                    TextSpan(
                      text: _JsonDiffPageState._short(change.before),
                      style: mono.copyWith(
                        color: c.danger,
                        decoration: change.kind == JsonChangeKind.removed ? null : TextDecoration.lineThrough,
                      ),
                    ),
                  if (change.kind != JsonChangeKind.added && change.kind != JsonChangeKind.removed)
                    TextSpan(
                      text: '  →  ',
                      style: mono.copyWith(color: c.textSubtle),
                    ),
                  if (change.kind != JsonChangeKind.removed)
                    TextSpan(
                      text: _JsonDiffPageState._short(change.after),
                      style: mono.copyWith(color: c.success),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

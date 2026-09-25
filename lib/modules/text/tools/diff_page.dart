import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/toolbox/file_intake.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/buttons.dart';
import '../../../ui/widgets/code_area.dart';
import '../../../ui/widgets/editor_pane.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/workbench.dart';
import '../logic/diff.dart';
import '../text_module.dart';
import '../widgets/diff_view.dart';

const _a = '''Super Toolbox keeps every tool local.
Media, data and web tools live in one app.
Nothing is uploaded.
Fast by default.''';
const _b = '''Super Toolbox keeps every tool on your machine.
Media, data and web tools live in one app.
Nothing is ever uploaded.
Fast by default.
Beautiful, too.''';

class DiffPage extends StatefulWidget {
  const DiffPage({super.key});

  @override
  State<DiffPage> createState() => _DiffPageState();
}

class _DiffPageState extends State<DiffPage> with FileIntakeMixin {
  @override
  String get intakeId => 'diff';

  @override
  void onFiles(List<String> paths) async {
    final texts = [for (final p in paths.take(2)) await FileIntake.readText(p)];
    if (texts.length == 2) {
      if (texts[0] != null) _left.text = texts[0]!;
      if (texts[1] != null) _right.text = texts[1]!;
    } else if (texts.single != null) {
      // One file: fill whichever side still holds the sample, left first.
      (_left.text == _a || _left.text.isEmpty ? _left : _right).text = texts.single!;
    }
  }

  final _left = CodeLineEditingController.fromText(_a);
  final _right = CodeLineEditingController.fromText(_b);
  var _ignoreSpace = false, _ignoreCase = false, _onlyChanges = false;
  late TextDiffResult _result;

  @override
  void initState() {
    super.initState();
    _left.addListener(outsideBuild(_run));
    _right.addListener(outsideBuild(_run));
    _run();
  }

  @override
  void dispose() {
    _left.dispose();
    _right.dispose();
    super.dispose();
  }

  void _run() {
    _result = diffLines(_left.text, _right.text, ignoreWhitespace: _ignoreSpace, ignoreCase: _ignoreCase);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = _result;
    return ToolScaffold(
      tool: textTool('diff'),
      onFiles: onFiles,
      toolbar: ToolbarRow(
        trailing: AppButton(
          label: 'common.swap'.tr(),
          icon: Icons.swap_horiz_rounded,
          size: ButtonSize.sm,
          onPressed: () {
            final t = _left.text;
            _left.text = _right.text;
            _right.text = t;
          },
        ),
        children: [
          ToolbarField(
            label: 'diff.ignore_space'.tr(),
            child: AppSwitch(
              value: _ignoreSpace,
              onChanged: (v) {
                _ignoreSpace = v;
                _run();
              },
            ),
          ),
          ToolbarField(
            label: 'diff.ignore_case'.tr(),
            child: AppSwitch(
              value: _ignoreCase,
              onChanged: (v) {
                _ignoreCase = v;
                _run();
              },
            ),
          ),
          ToolbarField(
            label: 'diff.only_changes'.tr(),
            child: AppSwitch(value: _onlyChanges, onChanged: (v) => setState(() => _onlyChanges = v)),
          ),
        ],
      ),
      body: SplitPane(
        vertical: true,
        initial: 0.38,
        minExtent: 120,
        first: SplitPane(
          first: EditorPane(title: 'diff.original'.tr(), controller: _left, open: true),
          second: EditorPane(title: 'diff.changed'.tr(), controller: _right, open: true),
        ),
        second: Pane(
          title: 'diff.result'.tr(),
          icon: Icons.difference_outlined,
          actions: [
            CopyAction(
              text: () => unifiedDiff(r, from: 'original', to: 'changed'),
              label: 'diff.copy_patch'.tr(),
            ),
          ],
          footer: Row(
            children: [
              if (r.identical)
                StatusLine('diff.identical'.tr(), tone: StatusTone.success).expanded()
              else ...[
                _Stat(color: c.success, text: '+${r.added}'),
                _Stat(color: c.danger, text: '−${r.removed}'),
                _Stat(color: c.warning, text: '~${r.modified}'),
                const Spacer(),
              ],
            ],
          ),
          child: DiffView(result: r, onlyChanges: _onlyChanges),
        ),
      ),
    );
  }
}

extension on Widget {
  Widget expanded() => Expanded(child: this);
}

class _Stat extends StatelessWidget {
  const _Stat({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(5)),
      child: Text(
        text,
        style: TextStyles.mono.copyWith(fontSize: 11.5, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

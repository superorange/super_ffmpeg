import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/toolbox/file_intake.dart';
import '../../../ui/widgets/code_area.dart';
import '../../../ui/widgets/editor_pane.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/workbench.dart';
import '../logic/color_tools.dart';
import '../web_module.dart';

const _sample =
    '.card{display:flex;gap:12px;padding:16px 20px;border-radius:12px;background:#fff}'
    '.card:hover,.card:focus-within{box-shadow:0 8px 24px rgba(0,0,0,.12)}'
    '@media (max-width:600px){.card{flex-direction:column}}/* theme */:root{--accent:#7c6cff}';

class CssPage extends StatefulWidget {
  const CssPage({super.key});

  @override
  State<CssPage> createState() => _CssPageState();
}

class _CssPageState extends State<CssPage> with FileIntakeMixin {
  @override
  String get intakeId => 'css';

  @override
  void onFiles(List<String> paths) async {
    final text = await FileIntake.readText(paths.first);
    if (text != null) _input.text = text;
  }

  final _input = CodeLineEditingController.fromText(_sample);
  final _output = CodeLineEditingController();
  var _minify = false;
  var _indent = 2;

  @override
  void initState() {
    super.initState();
    _input.addListener(outsideBuild(_run));
    _run();
  }

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final out = _input.text.trim().isEmpty
        ? ''
        : _minify
        ? CssTools.minify(_input.text)
        : CssTools.format(_input.text, indent: _indent);
    if (_output.text != out) _output.text = out;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final inLen = _input.text.length, outLen = _output.text.length;
    return ToolScaffold(
      tool: webTool('css'),
      onFiles: onFiles,
      toolbar: ToolbarRow(
        children: [
          Segmented<bool>(
            expand: false,
            value: _minify,
            onChanged: (v) {
              setState(() => _minify = v);
              _run();
            },
            items: [
              ChoiceItem(false, 'json.format'.tr(), icon: Icons.format_align_left_rounded),
              ChoiceItem(true, 'json.minify'.tr(), icon: Icons.compress_rounded),
            ],
          ),
          if (!_minify)
            ToolbarField(
              label: 'json.indent'.tr(),
              child: Segmented<int>(
                expand: false,
                dense: true,
                value: _indent,
                onChanged: (v) {
                  setState(() => _indent = v);
                  _run();
                },
                items: const [ChoiceItem(2, '2'), ChoiceItem(4, '4')],
              ),
            ),
        ],
      ),
      body: SplitPane(
        first: EditorPane(
          title: 'CSS',
          controller: _input,
          language: CodeLang.css,
          open: true,
          openExtensions: const ['css', 'scss', 'less'],
        ),
        second: EditorPane(
          title: 'common.output'.tr(),
          controller: _output,
          language: CodeLang.css,
          readOnly: true,
          save: true,
          saveName: _minify ? 'style.min.css' : 'style.css',
          wordWrap: _minify,
          footer: StatusLine(
            inLen == 0 ? '' : '$inLen → $outLen ${'common.chars_unit'.tr()}  ·  ${(100 * outLen / inLen).round()}%',
          ),
        ),
      ),
    );
  }
}

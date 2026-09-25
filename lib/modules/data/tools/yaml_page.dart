import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';

import '../../../core/toolbox/file_intake.dart';
import '../../../ui/widgets/buttons.dart';
import '../../../ui/widgets/code_area.dart';
import '../../../ui/widgets/editor_pane.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/workbench.dart';
import '../data_module.dart';
import '../logic/converters.dart';
import '../logic/json_tools.dart';
import 'json_page.dart' show jsonSample;

class YamlPage extends StatefulWidget {
  const YamlPage({super.key});

  @override
  State<YamlPage> createState() => _YamlPageState();
}

class _YamlPageState extends State<YamlPage> with FileIntakeMixin {
  @override
  String get intakeId => 'json_yaml';

  @override
  void onFiles(List<String> paths) async {
    final text = await FileIntake.readText(paths.first);
    if (text == null) return;
    final yaml = paths.first.toLowerCase().endsWith('.yaml') || paths.first.toLowerCase().endsWith('.yml');
    setState(() => _toYaml = !yaml);
    _input.text = text;
  }

  final _input = CodeLineEditingController.fromText(jsonSample);
  final _output = CodeLineEditingController();
  var _toYaml = true;
  var _indent = 2;
  String? _error;

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
    var out = '';
    _error = null;
    final text = _input.text;
    if (text.trim().isNotEmpty) {
      try {
        if (_toYaml) {
          final p = JsonTools.parse(text);
          if (!p.ok) throw FormatException(p.error.toString());
          out = DataConvert.valueToYaml(p.value);
        } else {
          out = JsonTools.format(DataConvert.yamlToValue(text), indent: _indent);
        }
      } on YamlException catch (e) {
        _error = e.message + (e.span == null ? '' : ' (line ${e.span!.start.line + 1})');
      } on FormatException catch (e) {
        _error = e.message;
      }
    }
    if (_output.text != out) _output.text = out;
    if (mounted) setState(() {});
  }

  void _swap() {
    final out = _output.text;
    setState(() => _toYaml = !_toYaml);
    _input.text = out;
  }

  @override
  Widget build(BuildContext context) {
    final from = _toYaml ? 'JSON' : 'YAML';
    final to = _toYaml ? 'YAML' : 'JSON';
    return ToolScaffold(
      tool: dataTool('json_yaml'),
      onFiles: onFiles,
      toolbar: ToolbarRow(
        trailing: AppButton(
          label: 'common.swap'.tr(),
          icon: Icons.swap_horiz_rounded,
          size: ButtonSize.sm,
          onPressed: _output.text.isEmpty ? null : _swap,
        ),
        children: [
          Segmented<bool>(
            expand: false,
            value: _toYaml,
            onChanged: (v) {
              setState(() => _toYaml = v);
              _run();
            },
            items: const [ChoiceItem(true, 'JSON → YAML'), ChoiceItem(false, 'YAML → JSON')],
          ),
          if (!_toYaml)
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
          title: from,
          controller: _input,
          language: _toYaml ? CodeLang.json : CodeLang.yaml,
          open: true,
          footer: _error == null
              ? StatusLine('common.chars'.tr(namedArgs: {'n': '${_input.text.length}'}))
              : StatusLine(_error!, tone: StatusTone.danger),
        ),
        second: EditorPane(
          title: to,
          controller: _output,
          language: _toYaml ? CodeLang.yaml : CodeLang.json,
          readOnly: true,
          save: true,
          saveName: _toYaml ? 'data.yaml' : 'data.json',
        ),
      ),
    );
  }
}

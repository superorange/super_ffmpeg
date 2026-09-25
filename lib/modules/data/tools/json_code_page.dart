import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/code_area.dart';
import '../../../ui/widgets/editor_pane.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/workbench.dart';
import '../data_module.dart';
import '../logic/json_codegen.dart';
import '../logic/json_tools.dart';

const _sample = '''{
  "id": 1024,
  "user_name": "tian",
  "email": "hi@example.com",
  "score": 98.5,
  "is_active": true,
  "tags": ["pro", "beta"],
  "address": { "city": "Shanghai", "zip_code": "200000" },
  "orders": [
    { "order_id": "A1", "amount": 12, "paid_at": null },
    { "order_id": "A2", "amount": 30.5, "coupon": "SAVE5" }
  ]
}''';

class JsonCodePage extends StatefulWidget {
  const JsonCodePage({super.key});

  @override
  State<JsonCodePage> createState() => _JsonCodePageState();
}

class _JsonCodePageState extends State<JsonCodePage> {
  final _input = CodeLineEditingController.fromText(_sample);
  final _output = CodeLineEditingController();
  final _root = TextEditingController(text: 'Root');
  var _target = CodeTarget.typescript;
  String? _error;

  static const _labels = {
    CodeTarget.typescript: 'TypeScript',
    CodeTarget.dart: 'Dart',
    CodeTarget.go: 'Go',
    CodeTarget.swift: 'Swift',
    CodeTarget.kotlin: 'Kotlin',
  };

  static const _langs = {
    CodeTarget.typescript: CodeLang.typescript,
    CodeTarget.dart: CodeLang.dart,
    CodeTarget.go: CodeLang.go,
    CodeTarget.swift: CodeLang.swift,
    CodeTarget.kotlin: CodeLang.kotlin,
  };

  static const _ext = {
    CodeTarget.typescript: 'ts',
    CodeTarget.dart: 'dart',
    CodeTarget.go: 'go',
    CodeTarget.swift: 'swift',
    CodeTarget.kotlin: 'kt',
  };

  @override
  void initState() {
    super.initState();
    _input.addListener(outsideBuild(_run));
    _root.addListener(outsideBuild(_run));
    _run();
  }

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    _root.dispose();
    super.dispose();
  }

  void _run() {
    var out = '';
    _error = null;
    if (_input.text.trim().isNotEmpty) {
      final p = JsonTools.parse(_input.text);
      if (p.ok) {
        final name = _root.text.trim().isEmpty ? 'Root' : _root.text.trim();
        out = JsonCodegen(rootName: name).generate(p.value, _target);
      } else {
        _error = p.error.toString();
      }
    }
    if (_output.text != out) _output.text = out;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ToolScaffold(
      tool: dataTool('json_code'),
      toolbar: ToolbarRow(
        children: [
          Segmented<CodeTarget>(
            expand: false,
            value: _target,
            onChanged: (v) {
              setState(() => _target = v);
              _run();
            },
            items: [for (final e in _labels.entries) ChoiceItem(e.key, e.value)],
          ),
          ToolbarField(
            label: 'json_code.root'.tr(),
            child: SizedBox(
              width: 140,
              height: 32,
              child: TextField(
                controller: _root,
                style: TextStyles.mono.copyWith(fontSize: 12, color: c.text),
                decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
              ),
            ),
          ),
        ],
      ),
      body: SplitPane(
        initial: 0.42,
        first: EditorPane(
          title: 'JSON',
          controller: _input,
          language: CodeLang.json,
          open: true,
          footer: _error == null ? StatusLine('json_code.hint'.tr()) : StatusLine(_error!, tone: StatusTone.danger),
        ),
        second: EditorPane(
          title: _labels[_target]!,
          controller: _output,
          language: _langs[_target]!,
          readOnly: true,
          save: true,
          saveName: 'models.${_ext[_target]}',
        ),
      ),
    );
  }
}

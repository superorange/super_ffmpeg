import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../../core/toolbox/file_intake.dart';
import '../../../core/utils/format.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/buttons.dart';
import '../../../ui/widgets/code_area.dart';
import '../../../ui/widgets/editor_pane.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/workbench.dart';
import '../data_module.dart';
import '../logic/json_tools.dart';
import '../widgets/json_tree.dart';

enum _Mode { format, minify, escape, unescape }

const jsonSample = '''{
  "name": "Super Toolbox",
  "version": "0.3.0",
  "local": true,
  "modules": ["media", "data", "web", "encode"],
  "stats": { "tools": 36, "rating": 4.9, "downloads": null },
  "authors": [{ "name": "Tian", "role": "maker" }]
}''';

class JsonPage extends StatefulWidget {
  const JsonPage({super.key});

  @override
  State<JsonPage> createState() => _JsonPageState();
}

class _JsonPageState extends State<JsonPage> with FileIntakeMixin {
  @override
  String get intakeId => 'json';

  @override
  void onFiles(List<String> paths) async {
    final text = await FileIntake.readText(paths.first);
    if (text != null) _input.text = text;
  }

  final _input = CodeLineEditingController.fromText(jsonSample);
  final _output = CodeLineEditingController();
  final _query = TextEditingController();
  final _tree = GlobalKey<JsonTreeViewState>();

  var _mode = _Mode.format;
  var _indent = 2;
  var _sort = false;
  var _treeView = false;
  JsonParse? _parse;
  Object? _shown;
  String? _error;
  String? _queryError;

  @override
  void initState() {
    super.initState();
    _input.addListener(outsideBuild(_run));
    _query.addListener(outsideBuild(_run));
    _run();
  }

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    _query.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text;
    String out = '';
    _error = null;
    _queryError = null;
    _parse = null;
    if (text.trim().isEmpty) {
      _shown = null;
    } else if (_mode == _Mode.escape) {
      out = JsonTools.escape(text);
    } else if (_mode == _Mode.unescape) {
      try {
        out = JsonTools.unescape(text);
      } on FormatException catch (e) {
        _error = e.message;
      }
    } else {
      _parse = JsonTools.parse(text);
      if (_parse!.ok) {
        Object? value = _parse!.value;
        if (_query.text.trim().isNotEmpty) {
          try {
            final hits = JsonTools.query(value, _query.text);
            value = hits.length == 1 ? hits.single : hits;
          } on FormatException catch (e) {
            _queryError = e.message;
          }
        }
        _shown = value;
        out = _mode == _Mode.minify
            ? JsonTools.minify(value, sortKeys: _sort)
            : JsonTools.format(value, indent: _indent, sortKeys: _sort);
      } else {
        _error = _parse!.error.toString();
      }
    }
    if (_output.text != out) _output.text = out;
    if (mounted) setState(() {});
  }

  void _jumpToError() {
    final e = _parse?.error;
    if (e?.line == null) return;
    _input.selection = CodeLineSelection.collapsed(index: e!.line! - 1, offset: (e.column! - 1).clamp(0, 1 << 20));
    _input.makeCursorVisible();
  }

  void _set(VoidCallback f) {
    f();
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final structured = _mode == _Mode.format || _mode == _Mode.minify;
    final stats = _parse?.ok == true ? JsonTools.stats(_parse!.value) : null;

    final toolbar = ToolbarRow(
      trailing: AppButton.ghost(
        label: 'common.sample'.tr(),
        icon: Icons.auto_awesome_outlined,
        size: ButtonSize.sm,
        onPressed: () => _input.text = jsonSample,
      ),
      children: [
        Segmented<_Mode>(
          expand: false,
          value: _mode,
          onChanged: (v) => _set(() => _mode = v),
          items: [
            ChoiceItem(_Mode.format, 'json.format'.tr(), icon: Icons.format_align_left_rounded),
            ChoiceItem(_Mode.minify, 'json.minify'.tr(), icon: Icons.compress_rounded),
            ChoiceItem(_Mode.escape, 'json.escape'.tr()),
            ChoiceItem(_Mode.unescape, 'json.unescape'.tr()),
          ],
        ),
        if (_mode == _Mode.format)
          ToolbarField(
            label: 'json.indent'.tr(),
            child: Segmented<int>(
              expand: false,
              dense: true,
              value: _indent,
              onChanged: (v) => _set(() => _indent = v),
              items: const [ChoiceItem(2, '2'), ChoiceItem(4, '4'), ChoiceItem(0, 'Tab')],
            ),
          ),
        if (structured)
          ToolbarField(
            label: 'json.sort_keys'.tr(),
            child: AppSwitch(value: _sort, onChanged: (v) => _set(() => _sort = v)),
          ),
        if (structured)
          SizedBox(
            width: 260,
            height: 32,
            child: TextField(
              controller: _query,
              style: TextStyles.mono.copyWith(fontSize: 12, color: c.text),
              decoration: InputDecoration(
                hintText: r'JSONPath  $.items[*].name',
                prefixIcon: Icon(Icons.filter_alt_outlined, size: 15, color: c.textSubtle),
                prefixIconConstraints: const BoxConstraints(minWidth: 30),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                errorText: null,
              ),
            ),
          ),
      ],
    );

    final inputFooter = _error != null
        ? Row(
            children: [
              Expanded(child: StatusLine(_error!, tone: StatusTone.danger)),
              if (_parse?.error?.line != null)
                AppButton.ghost(label: 'json.jump'.tr(), size: ButtonSize.sm, onPressed: _jumpToError),
            ],
          )
        : _queryError != null
        ? StatusLine(_queryError!, tone: StatusTone.warning)
        : StatusLine(
            stats != null
                ? 'json.valid'.tr(
                    namedArgs: {
                      'objects': '${stats.objects}',
                      'arrays': '${stats.arrays}',
                      'values': '${stats.values}',
                      'depth': '${stats.depth}',
                    },
                  )
                : 'common.chars'.tr(namedArgs: {'n': '${_input.text.length}'}),
            tone: stats != null ? StatusTone.success : StatusTone.neutral,
          );

    final outputHeader = structured
        ? Segmented<bool>(
            expand: false,
            dense: true,
            value: _treeView,
            onChanged: (v) => setState(() => _treeView = v),
            items: [
              ChoiceItem(false, 'json.text'.tr(), icon: Icons.notes_rounded),
              ChoiceItem(true, 'json.tree'.tr(), icon: Icons.account_tree_outlined),
            ],
          )
        : null;

    final output = _treeView && structured
        ? Pane(
            title: 'common.output'.tr(),
            headerExtra: outputHeader,
            color: c.codeBg,
            actions: [
              PaneAction(
                icon: Icons.unfold_more_rounded,
                tooltip: 'json.expand_all'.tr(),
                onPressed: () => _tree.currentState?.expandAll(),
              ),
              PaneAction(
                icon: Icons.unfold_less_rounded,
                tooltip: 'json.collapse_all'.tr(),
                onPressed: () => _tree.currentState?.collapseAll(),
              ),
              CopyAction(text: () => _output.text),
            ],
            footer: StatusLine(Fmt.bytes(utf8.encode(_output.text).length)),
            child: _shown == null && _parse?.ok != true ? const SizedBox() : JsonTreeView(key: _tree, value: _shown),
          )
        : EditorPane(
            title: 'common.output'.tr(),
            controller: _output,
            language: _mode == _Mode.unescape ? CodeLang.plain : CodeLang.json,
            readOnly: true,
            headerExtra: outputHeader,
            save: true,
            saveName: 'formatted.json',
            wordWrap: _mode != _Mode.format,
            footer: StatusLine(
              '${Fmt.bytes(utf8.encode(_output.text).length)}'
              '${_input.text.isNotEmpty && _output.text.isNotEmpty ? '  ·  ${(100 * utf8.encode(_output.text).length / utf8.encode(_input.text).length).round()}%' : ''}',
            ),
          );

    return ToolScaffold(
      tool: dataTool('json'),
      onFiles: onFiles,
      toolbar: toolbar,
      body: SplitPane(
        first: EditorPane(
          title: 'common.input'.tr(),
          controller: _input,
          language: _mode == _Mode.escape ? CodeLang.plain : CodeLang.json,
          open: true,
          openExtensions: const ['json', 'txt', 'geojson', 'jsonc'],
          hint: 'json.hint'.tr(),
          footer: inputFooter,
        ),
        second: output,
      ),
    );
  }
}

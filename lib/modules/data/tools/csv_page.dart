import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/toolbox/file_intake.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/buttons.dart';
import '../../../ui/widgets/code_area.dart';
import '../../../ui/widgets/editor_pane.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/workbench.dart';
import '../data_module.dart';
import '../logic/converters.dart';
import '../logic/json_tools.dart';

const _sample =
    'name,city,age,member\nAlice,Shanghai,30,true\n"Bob, Jr.",Beijing,25,false\nCarol,"New ""York""",41,true\n';

class CsvPage extends StatefulWidget {
  const CsvPage({super.key});

  @override
  State<CsvPage> createState() => _CsvPageState();
}

class _CsvPageState extends State<CsvPage> with FileIntakeMixin {
  @override
  String get intakeId => 'csv_json';

  @override
  void onFiles(List<String> paths) async {
    final text = await FileIntake.readText(paths.first);
    if (text == null) return;
    final lower = paths.first.toLowerCase();
    setState(() {
      _toJson = !lower.endsWith('.json');
      if (lower.endsWith('.tsv')) _delimiter = '\t';
    });
    _input.text = text;
  }

  final _input = CodeLineEditingController.fromText(_sample);
  final _output = CodeLineEditingController();
  var _toJson = true;
  var _delimiter = ',';
  var _infer = true;
  var _table = false;
  List<List<String>> _rows = const [];
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
    try {
      if (text.trim().isNotEmpty) {
        if (_toJson) {
          _rows = DataConvert.parseCsv(text, delimiter: _delimiter);
          out = JsonTools.format(DataConvert.csvToObjects(text, delimiter: _delimiter, inferTypes: _infer));
        } else {
          final p = JsonTools.parse(text);
          if (!p.ok) throw FormatException(p.error.toString());
          out = DataConvert.valueToCsv(p.value, delimiter: _delimiter);
          _rows = DataConvert.parseCsv(out, delimiter: _delimiter);
        }
      } else {
        _rows = const [];
      }
    } on FormatException catch (e) {
      _error = e.message;
      _rows = const [];
    }
    if (_output.text != out) _output.text = out;
    if (mounted) setState(() {});
  }

  void _set(VoidCallback f) {
    setState(f);
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final output = _table
        ? Pane(
            title: 'csv.table'.tr(),
            headerExtra: _viewSwitch(),
            footer: StatusLine('csv.rows'.tr(namedArgs: {'n': '${(_rows.length - 1).clamp(0, 1 << 30)}'})),
            child: _rows.isEmpty ? const SizedBox() : _CsvTable(rows: _rows),
          )
        : EditorPane(
            title: _toJson ? 'JSON' : 'CSV',
            controller: _output,
            language: _toJson ? CodeLang.json : CodeLang.plain,
            readOnly: true,
            save: true,
            headerExtra: _viewSwitch(),
            saveName: _toJson ? 'data.json' : 'data.csv',
          );
    return ToolScaffold(
      tool: dataTool('csv_json'),
      onFiles: onFiles,
      toolbar: ToolbarRow(
        trailing: AppButton(
          label: 'common.swap'.tr(),
          icon: Icons.swap_horiz_rounded,
          size: ButtonSize.sm,
          onPressed: _output.text.isEmpty
              ? null
              : () {
                  final out = _output.text;
                  _set(() => _toJson = !_toJson);
                  _input.text = out;
                },
        ),
        children: [
          Segmented<bool>(
            expand: false,
            value: _toJson,
            onChanged: (v) => _set(() => _toJson = v),
            items: const [ChoiceItem(true, 'CSV → JSON'), ChoiceItem(false, 'JSON → CSV')],
          ),
          ToolbarField(
            label: 'csv.delimiter'.tr(),
            child: Segmented<String>(
              expand: false,
              dense: true,
              value: _delimiter,
              onChanged: (v) => _set(() => _delimiter = v),
              items: [
                const ChoiceItem(',', ','),
                const ChoiceItem(';', ';'),
                ChoiceItem('\t', 'Tab'),
                const ChoiceItem('|', '|'),
              ],
            ),
          ),
          if (_toJson)
            ToolbarField(
              label: 'csv.infer'.tr(),
              child: AppSwitch(value: _infer, onChanged: (v) => _set(() => _infer = v)),
            ),
        ],
      ),
      body: SplitPane(
        first: EditorPane(
          title: _toJson ? 'CSV' : 'JSON',
          controller: _input,
          language: _toJson ? CodeLang.plain : CodeLang.json,
          open: true,
          openExtensions: const ['csv', 'tsv', 'txt', 'json'],
          footer: _error == null
              ? StatusLine('common.chars'.tr(namedArgs: {'n': '${_input.text.length}'}))
              : StatusLine(_error!, tone: StatusTone.danger),
        ),
        second: DefaultTextStyle.merge(
          style: TextStyle(color: c.text),
          child: output,
        ),
      ),
    );
  }

  Widget _viewSwitch() => Segmented<bool>(
    expand: false,
    dense: true,
    value: _table,
    onChanged: (v) => setState(() => _table = v),
    items: [
      ChoiceItem(false, 'json.text'.tr(), icon: Icons.notes_rounded),
      ChoiceItem(true, 'csv.table'.tr(), icon: Icons.table_rows_outlined),
    ],
  );
}

class _CsvTable extends StatelessWidget {
  const _CsvTable({required this.rows});
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cols = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    Widget cell(String text, {bool header = false}) => Container(
      constraints: const BoxConstraints(minWidth: 80, maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: header ? c.surfaceAlt : null,
        border: Border(
          right: BorderSide(color: c.border),
          bottom: BorderSide(color: c.border),
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: (header ? TextStyles.label.copyWith(fontWeight: FontWeight.w600) : TextStyles.body).copyWith(
          color: c.text,
        ),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            for (var i = 0; i < rows.length; i++)
              TableRow(
                children: [
                  for (var j = 0; j < cols; j++) cell(j < rows[i].length ? rows[i][j] : '', header: i == 0),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

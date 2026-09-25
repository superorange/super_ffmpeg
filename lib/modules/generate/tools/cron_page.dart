import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/workbench.dart';
import '../generate_module.dart';
import '../logic/time_tools.dart';

class CronPage extends StatefulWidget {
  const CronPage({super.key});

  @override
  State<CronPage> createState() => _CronPageState();
}

class _CronPageState extends State<CronPage> {
  final _expr = TextEditingController(text: '*/15 9-18 * * MON-FRI');

  static const _presets = {
    '* * * * *': 'cron.p_every_minute',
    '*/5 * * * *': 'cron.p_every_5',
    '0 * * * *': 'cron.p_hourly',
    '0 9 * * *': 'cron.p_daily_9',
    '0 9 * * 1-5': 'cron.p_weekdays',
    '0 0 * * 0': 'cron.p_weekly',
    '0 0 1 * *': 'cron.p_monthly',
    '0 3 1 1 *': 'cron.p_yearly',
  };

  @override
  void initState() {
    super.initState();
    _expr.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _expr.dispose();
    super.dispose();
  }

  String _describe(Set<int> values, int min, int max, [List<String>? names]) {
    if (values.length == max - min + 1) return 'cron.every'.tr();
    final sorted = values.toList()..sort();
    // Compress consecutive runs into ranges.
    final parts = <String>[];
    var i = 0;
    String name(int v) => names == null ? '$v' : names[v - min];
    while (i < sorted.length) {
      var j = i;
      while (j + 1 < sorted.length && sorted[j + 1] == sorted[j] + 1) {
        j++;
      }
      parts.add(
        j - i >= 2
            ? '${name(sorted[i])}–${name(sorted[j])}'
            : [for (var k = i; k <= j; k++) name(sorted[k])].join(', '),
      );
      i = j + 1;
    }
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    CronExpression? cron;
    String? error;
    try {
      cron = CronExpression.parse(_expr.text);
    } on FormatException catch (e) {
      error = e.message;
    }
    final now = DateTime.now();
    final runs = cron?.next(12, from: now) ?? const <DateTime>[];
    final weekdayNames = [for (var d = 0; d < 7; d++) 'time.weekdays.${d == 0 ? 7 : d}'.tr()];
    final fields = cron == null
        ? const <(String, String, String)>[]
        : [
            ('cron.minute'.tr(), '0–59', _describe(cron.minutes, 0, 59)),
            ('cron.hour'.tr(), '0–23', _describe(cron.hours, 0, 23)),
            ('cron.day'.tr(), '1–31', _describe(cron.days, 1, 31)),
            ('cron.month'.tr(), '1–12', _describe(cron.months, 1, 12)),
            ('cron.weekday'.tr(), '0–6', _describe(cron.weekdays, 0, 6, weekdayNames)),
          ];

    return ToolScaffold(
      tool: generateTool('cron'),
      toolbar: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _expr,
            style: TextStyles.mono.copyWith(fontSize: 20, fontWeight: FontWeight.w600, color: c.text, letterSpacing: 1),
            decoration: InputDecoration(
              errorText: error,
              hintText: 'm h dom mon dow',
              helperText: 'cron.syntax'.tr(),
            ),
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in _presets.entries)
                SelectableChip(
                  label: e.value.tr(),
                  tooltip: e.key,
                  selected: _expr.text.trim() == e.key,
                  onTap: () => _expr.text = e.key,
                ),
            ],
          ),
        ],
      ),
      body: SplitPane(
        first: Pane(
          title: 'cron.fields'.tr(),
          icon: Icons.view_column_outlined,
          padding: const EdgeInsets.all(6),
          child: ListView(
            children: [
              for (final (name, range, desc) in fields) ValueRow(label: name, hint: range, value: desc, mono: false),
            ],
          ),
        ),
        second: Pane(
          title: 'cron.next_runs'.tr(),
          icon: Icons.event_available_rounded,
          padding: const EdgeInsets.all(6),
          child: ListView(
            children: [
              for (final (i, r) in runs.indexed)
                () {
                  final (n, unit, _) = TimeTools.relative(r, now);
                  return ValueRow(
                    label: '#${i + 1}',
                    value: '${TimeTools.dateTime(r)}  ${'time.weekdays.${r.weekday}'.tr()}',
                    hint: 'time.in'.tr(namedArgs: {'n': '$n', 'unit': 'time.units.$unit'.tr()}),
                  );
                }(),
            ],
          ),
        ),
      ),
    );
  }
}

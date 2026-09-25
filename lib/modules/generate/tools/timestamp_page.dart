import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/workbench.dart';
import '../generate_module.dart';
import '../logic/time_tools.dart';

class TimestampPage extends StatefulWidget {
  const TimestampPage({super.key});

  @override
  State<TimestampPage> createState() => _TimestampPageState();
}

class _TimestampPageState extends State<TimestampPage> {
  final _input = TextEditingController(text: '${DateTime.now().millisecondsSinceEpoch ~/ 1000}');
  late Timer _tick;
  var _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() => _now = DateTime.now()));
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final parsed = TimeTools.parse(_input.text);
    final t = parsed?.time;
    final local = t?.toLocal();
    final rel = t == null ? null : TimeTools.relative(t, _now);
    final rows = t == null
        ? const <(String, String)>[]
        : [
            ('time.local'.tr(), '${TimeTools.dateTime(local!)}  (UTC${TimeTools.offsetOf(local)})'),
            ('UTC', TimeTools.dateTime(t.toUtc())),
            ('ISO 8601', TimeTools.iso(local)),
            ('RFC 2822', TimeTools.rfc2822(t)),
            ('Unix (s)', '${t.millisecondsSinceEpoch ~/ 1000}'),
            ('Unix (ms)', '${t.millisecondsSinceEpoch}'),
            (
              'time.relative'.tr(),
              'time.${rel!.$3 ? 'in' : 'ago'}'.tr(namedArgs: {'n': '${rel.$1}', 'unit': 'time.units.${rel.$2}'.tr()}),
            ),
            (
              'time.calendar'.tr(),
              'time.calendar_value'.tr(
                namedArgs: {
                  'weekday': 'time.weekdays.${local.weekday}'.tr(),
                  'week': '${TimeTools.isoWeek(local)}',
                  'day': '${TimeTools.dayOfYear(local)}',
                },
              ),
            ),
          ];

    final clock = Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.panel),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.accent.withValues(alpha: 0.16), c.accent2.withValues(alpha: 0.08)],
        ),
        border: Border.all(color: c.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('time.now'.tr(), style: TextStyles.label.copyWith(color: c.textMuted)),
                const SizedBox(height: 4),
                SelectableText(
                  '${_now.millisecondsSinceEpoch ~/ 1000}',
                  style: TextStyles.mono.copyWith(fontSize: 30, fontWeight: FontWeight.w700, color: c.text),
                ),
                Text(
                  '${_now.millisecondsSinceEpoch} ms  ·  ${TimeTools.dateTime(_now)}',
                  style: TextStyles.mono.copyWith(fontSize: 12, color: c.textMuted),
                ),
              ],
            ),
          ),
          CopyAction(text: () => '${_now.millisecondsSinceEpoch ~/ 1000}', label: 's'),
          CopyAction(text: () => '${_now.millisecondsSinceEpoch}', label: 'ms'),
        ],
      ),
    );

    return ToolScaffold(
      tool: generateTool('timestamp'),
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          clock,
          const SizedBox(height: Space.lg),
          TextField(
            controller: _input,
            style: TextStyles.mono.copyWith(fontSize: 15, color: c.text),
            decoration: InputDecoration(
              labelText: 'time.input'.tr(),
              hintText: '1700000000 · 1700000000000 · 2026-09-25 13:26:00 · 2026-09-25T05:26:00Z',
              prefixIcon: Icon(Icons.schedule_rounded, color: c.textSubtle),
              suffixIcon: TextButton(
                onPressed: () => _input.text = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
                child: Text('time.use_now'.tr()),
              ),
              errorText: _input.text.trim().isNotEmpty && parsed == null ? 'time.invalid'.tr() : null,
              helperText: parsed == null ? null : 'time.source.${parsed.source.replaceAll(':', '_')}'.tr(),
            ),
          ),
          const SizedBox(height: Space.lg),
          if (rows.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(Radii.card),
                border: Border.all(color: c.border),
                boxShadow: c.cardShadow,
              ),
              child: Column(
                children: [for (final (k, v) in rows) ValueRow(label: k, value: v)],
              ),
            ),
        ],
      ),
    );
  }
}

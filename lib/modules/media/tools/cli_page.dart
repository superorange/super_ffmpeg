import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/layout.dart';
import '../builders/cli.dart';
import '../engine/command_plan.dart';
import '../studio/tool_panel.dart';

class CliTool extends ConsumerStatefulWidget {
  const CliTool({super.key});

  @override
  ConsumerState<CliTool> createState() => _CliToolState();
}

class _CliToolState extends ConsumerState<CliTool> {
  final _args = TextEditingController(text: cliTemplates.first.args);

  @override
  void initState() {
    super.initState();
    _args.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _args.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final template = _args.text;

    final header = OptionField(
      label: 'media.cli.args'.tr(),
      hint: 'media.cli.args_hint'.tr(),
      child: TextField(
        controller: _args,
        minLines: 3,
        maxLines: 8,
        style: TextStyles.mono.copyWith(color: c.text),
        decoration: const InputDecoration(prefixText: 'ffmpeg '),
      ),
    );

    final fields = <Widget>[
      OptionField(
        label: 'media.cli.templates'.tr(),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in cliTemplates)
              SelectableChip(
                label: t.labelKey.tr(),
                selected: template == t.args,
                onTap: () => _args.text = t.args,
              ),
          ],
        ),
      ),
    ];

    return StudioToolView(
      toolId: 'cli',
      actionKey: 'media.cli.action',
      header: header,
      fields: fields,
      scope: InputScope.optional,
      range: RangeUsage.none,
      planner: (r) {
        if (!cliUsesInput(template)) {
          return [
            PlannedJob(
              inputs: const [],
              plan: buildCli(template: template),
            ),
          ];
        }
        if (r.inputs.isEmpty) throw const PlanException('media.errors.cli_needs_input');
        return [
          for (final input in r.inputs)
            PlannedJob(
              inputs: [input],
              plan: buildCli(template: template, input: input, info: r.infos[input]),
            ),
        ];
      },
    );
  }
}

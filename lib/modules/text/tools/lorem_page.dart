import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/buttons.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/workbench.dart';
import '../logic/text_tools.dart';
import '../text_module.dart';

class LoremPage extends StatefulWidget {
  const LoremPage({super.key});

  @override
  State<LoremPage> createState() => _LoremPageState();
}

class _LoremPageState extends State<LoremPage> {
  var _chinese = false;
  var _paragraphs = 3.0;
  var _sentences = 5.0;
  var _seed = Random().nextInt(1 << 30);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = TextTools.lorem(
      paragraphs: _paragraphs.round(),
      sentences: _sentences.round(),
      chinese: _chinese,
      seed: _seed,
    );
    return ToolScaffold(
      tool: textTool('lorem'),
      toolbar: ToolbarRow(
        trailing: AppButton(
          label: 'lorem.regenerate'.tr(),
          icon: Icons.refresh_rounded,
          size: ButtonSize.sm,
          onPressed: () => setState(() => _seed = Random().nextInt(1 << 30)),
        ),
        children: [
          Segmented<bool>(
            expand: false,
            value: _chinese,
            onChanged: (v) => setState(() => _chinese = v),
            items: const [ChoiceItem(false, 'Lorem ipsum'), ChoiceItem(true, '中文')],
          ),
          SizedBox(
            width: 240,
            child: ToolbarField(
              label: 'lorem.paragraphs'.tr(),
              child: Expanded(
                child: LabeledSlider(
                  value: _paragraphs,
                  min: 1,
                  max: 20,
                  divisions: 19,
                  format: (v) => '${v.round()}',
                  onChanged: (v) => setState(() => _paragraphs = v),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 240,
            child: ToolbarField(
              label: 'lorem.sentences'.tr(),
              child: Expanded(
                child: LabeledSlider(
                  value: _sentences,
                  min: 1,
                  max: 15,
                  divisions: 14,
                  format: (v) => '${v.round()}',
                  onChanged: (v) => setState(() => _sentences = v),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Pane(
        title: 'common.output'.tr(),
        actions: [CopyAction(text: () => text, label: 'common.copy'.tr())],
        footer: StatusLine('common.chars'.tr(namedArgs: {'n': '${text.length}'})),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: SelectableText(text, style: TextStyles.body.copyWith(fontSize: 14, height: 1.75, color: c.text)),
        ),
      ),
    );
  }
}

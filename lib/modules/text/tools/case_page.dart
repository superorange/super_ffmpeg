import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../ui/widgets/workbench.dart';
import '../logic/text_tools.dart';
import '../text_module.dart';

class CasePage extends StatefulWidget {
  const CasePage({super.key});

  @override
  State<CasePage> createState() => _CasePageState();
}

class _CasePageState extends State<CasePage> {
  final _input = TextEditingController(text: 'user profile settingsURL');

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ToolScaffold(
      tool: textTool('case'),
      body: SplitPane(
        initial: 0.4,
        first: Pane(
          title: 'common.input'.tr(),
          actions: [
            PaneAction(
              icon: Icons.content_paste_rounded,
              tooltip: 'common.paste'.tr(),
              onPressed: () async => _input.text = await readClipboard() ?? _input.text,
            ),
            PaneAction(icon: Icons.backspace_outlined, tooltip: 'common.clear'.tr(), onPressed: _input.clear),
          ],
          footer: StatusLine('case.hint'.tr()),
          child: TextArea(controller: _input),
        ),
        second: Pane(
          title: 'case.results'.tr(),
          padding: const EdgeInsets.all(6),
          child: ListView(
            children: [
              for (final s in CaseStyle.values)
                ValueRow(label: s.example, value: TextTools.convertCase(_input.text, s)),
            ],
          ),
        ),
      ),
    );
  }
}

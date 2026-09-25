import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/buttons.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/workbench.dart';
import '../../generate/logic/time_tools.dart';
import '../generate_module.dart';
import '../logic/generators.dart';

class UuidPage extends StatefulWidget {
  const UuidPage({super.key});

  @override
  State<UuidPage> createState() => _UuidPageState();
}

class _UuidPageState extends State<UuidPage> {
  var _kind = IdKind.uuid4;
  var _count = 10;
  var _upper = false;
  var _hyphens = true;
  var _ids = <String>[];
  final _inspect = TextEditingController();

  static const _labels = {
    IdKind.uuid4: 'UUID v4',
    IdKind.uuid7: 'UUID v7',
    IdKind.ulid: 'ULID',
    IdKind.nanoid: 'Nano ID',
    IdKind.objectId: 'ObjectId',
  };

  @override
  void initState() {
    super.initState();
    _generate();
    _inspect.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _inspect.dispose();
    super.dispose();
  }

  void _generate() => setState(() {
    _ids = [for (var i = 0; i < _count; i++) Ids.generate(_kind, upper: _upper, hyphens: _hyphens)];
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final uuidLike = _kind == IdKind.uuid4 || _kind == IdKind.uuid7;
    final ts = Ids.timestampOf(_inspect.text);
    return ToolScaffold(
      tool: generateTool('uuid'),
      toolbar: ToolbarRow(
        trailing: AppButton.primary(
          label: 'uuid.generate'.tr(),
          icon: Icons.refresh_rounded,
          size: ButtonSize.sm,
          onPressed: _generate,
        ),
        children: [
          Segmented<IdKind>(
            expand: false,
            value: _kind,
            onChanged: (v) {
              _kind = v;
              _generate();
            },
            items: [for (final e in _labels.entries) ChoiceItem(e.key, e.value)],
          ),
          ToolbarField(
            label: 'uuid.count'.tr(),
            child: Segmented<int>(
              expand: false,
              dense: true,
              value: _count,
              onChanged: (v) {
                _count = v;
                _generate();
              },
              items: const [ChoiceItem(1, '1'), ChoiceItem(10, '10'), ChoiceItem(50, '50'), ChoiceItem(100, '100')],
            ),
          ),
          if (_kind != IdKind.nanoid && _kind != IdKind.ulid)
            ToolbarField(
              label: 'hash.uppercase'.tr(),
              child: AppSwitch(
                value: _upper,
                onChanged: (v) {
                  _upper = v;
                  _generate();
                },
              ),
            ),
          if (uuidLike)
            ToolbarField(
              label: 'uuid.hyphens'.tr(),
              child: AppSwitch(
                value: _hyphens,
                onChanged: (v) {
                  _hyphens = v;
                  _generate();
                },
              ),
            ),
        ],
      ),
      body: SplitPane(
        initial: 0.62,
        first: Pane(
          title: _labels[_kind],
          icon: Icons.format_list_bulleted_rounded,
          actions: [CopyAction(text: () => _ids.join('\n'), label: 'uuid.copy_all'.tr())],
          footer: StatusLine('uuid.${_kind.name}_desc'.tr()),
          padding: const EdgeInsets.all(6),
          child: ListView.builder(
            itemCount: _ids.length,
            itemBuilder: (_, i) => ValueRow(label: '#${i + 1}', value: _ids[i]),
          ),
        ),
        second: Pane(
          title: 'uuid.inspect'.tr(),
          icon: Icons.search_rounded,
          padding: const EdgeInsets.all(Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _inspect,
                style: TextStyles.mono.copyWith(fontSize: 12.5, color: c.text),
                decoration: InputDecoration(hintText: 'uuid.inspect_hint'.tr()),
              ),
              const SizedBox(height: Space.md),
              if (_inspect.text.trim().isNotEmpty)
                ts == null
                    ? StatusLine('uuid.no_time'.tr())
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ValueRow(label: 'uuid.created'.tr(), value: TimeTools.dateTime(ts)),
                          ValueRow(label: 'Unix ms', value: '${ts.millisecondsSinceEpoch}'),
                          ValueRow(label: 'ISO 8601', value: ts.toUtc().toIso8601String()),
                        ],
                      ),
            ],
          ),
        ),
      ),
    );
  }
}

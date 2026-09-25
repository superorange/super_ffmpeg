import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/buttons.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/layout.dart';
import '../../../ui/widgets/workbench.dart';
import '../generate_module.dart';
import '../logic/generators.dart';

class PasswordPage extends StatefulWidget {
  const PasswordPage({super.key});

  @override
  State<PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends State<PasswordPage> {
  var _o = const PasswordOptions();
  late var _password = Passwords.generate(_o);
  var _batch = <String>[];

  void _set(PasswordOptions o) {
    if (Passwords.sets(o).isEmpty) return;
    setState(() {
      _o = o;
      _password = Passwords.generate(o);
      _batch = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bits = Passwords.entropy(_o);
    final (label, color, level) = bits < 40
        ? ('password.weak'.tr(), c.danger, 0.25)
        : bits < 64
        ? ('password.fair'.tr(), c.warning, 0.5)
        : bits < 100
        ? ('password.strong'.tr(), c.success, 0.78)
        : ('password.very_strong'.tr(), c.success, 1.0);

    final hero = Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.panel),
        border: Border.all(color: c.border),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  _password,
                  style: TextStyles.mono.copyWith(
                    fontSize: 22,
                    color: c.text,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: Space.md),
              AppIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'lorem.regenerate'.tr(),
                size: 36,
                onPressed: () => setState(() => _password = Passwords.generate(_o)),
              ),
              AppButton.primary(
                label: 'common.copy'.tr(),
                icon: Icons.copy_rounded,
                onPressed: () => CopyAction.copy(context, _password),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(value: level, color: color, minHeight: 6),
                ),
              ),
              const SizedBox(width: Space.md),
              Text(
                '$label · ${bits.round()} bits',
                style: TextStyles.label.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );

    final options = Panel(
      title: 'password.options'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OptionField(
            label: 'password.length'.tr(),
            child: LabeledSlider(
              value: _o.length.toDouble(),
              min: 4,
              max: 128,
              format: (v) => '${v.round()}',
              onChanged: (v) => _set(_o.copyWith(length: v.round())),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SelectableChip(
                label: 'a–z',
                selected: _o.lower,
                onTap: () => _set(_o.copyWith(lower: !_o.lower)),
              ),
              SelectableChip(
                label: 'A–Z',
                selected: _o.upper,
                onTap: () => _set(_o.copyWith(upper: !_o.upper)),
              ),
              SelectableChip(
                label: '0–9',
                selected: _o.digits,
                onTap: () => _set(_o.copyWith(digits: !_o.digits)),
              ),
              SelectableChip(
                label: '!@#\$',
                selected: _o.symbols,
                onTap: () => _set(_o.copyWith(symbols: !_o.symbols)),
              ),
              SelectableChip(
                label: 'password.no_ambiguous'.tr(),
                selected: _o.excludeAmbiguous,
                onTap: () => _set(_o.copyWith(excludeAmbiguous: !_o.excludeAmbiguous)),
              ),
            ],
          ),
        ],
      ),
    );

    return ToolScaffold(
      tool: generateTool('password'),
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          hero,
          const SizedBox(height: Space.lg),
          options,
          const SizedBox(height: Space.lg),
          Row(
            children: [
              AppButton(
                label: 'password.batch'.tr(),
                icon: Icons.playlist_add_rounded,
                onPressed: () => setState(() => _batch = [for (var i = 0; i < 10; i++) Passwords.generate(_o)]),
              ),
              const Spacer(),
              if (_batch.isNotEmpty) CopyAction(text: () => _batch.join('\n'), label: 'uuid.copy_all'.tr()),
            ],
          ),
          if (_batch.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Panel(
              padding: const EdgeInsets.all(6),
              child: Column(
                children: [for (final p in _batch) ValueRow(label: '', value: p)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

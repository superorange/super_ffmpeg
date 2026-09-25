import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/workbench.dart';
import '../encode_module.dart';
import '../logic/number_base.dart';

class NumberBasePage extends StatefulWidget {
  const NumberBasePage({super.key});

  @override
  State<NumberBasePage> createState() => _NumberBasePageState();
}

class _NumberBasePageState extends State<NumberBasePage> {
  final _input = TextEditingController(text: '255');
  var _radix = 10;
  var _bits = 32;
  BigInt? _value;
  String? _error;

  @override
  void initState() {
    super.initState();
    _input.addListener(_parse);
    _parse();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _parse() {
    try {
      _value = _input.text.trim().isEmpty ? null : NumberBase.parse(_input.text, _radix);
      _error = null;
    } on FormatException catch (e) {
      _value = null;
      _error = e.message;
    }
    setState(() {});
  }

  void _setValue(BigInt v) => _input.text = NumberBase.format(v, _radix);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = _value;
    final rows = v == null
        ? const <(String, String)>[]
        : [
            ('number_base.bin'.tr(), NumberBase.format(v, 2, group: true)),
            ('number_base.oct'.tr(), NumberBase.format(v, 8)),
            ('number_base.dec'.tr(), NumberBase.format(v, 10, group: true)),
            ('number_base.hex'.tr(), NumberBase.format(v, 16, upper: true, group: true)),
            ('Base32', NumberBase.format(v, 32)),
            ('Base36', NumberBase.format(v, 36)),
            if (v.bitLength <= 21 && !v.isNegative && v > BigInt.zero)
              ('number_base.char'.tr(), String.fromCharCode(v.toInt())),
          ];
    final fits = v != null && v.bitLength <= _bits - (v.isNegative ? 0 : 0);
    final bits = v == null || !fits ? null : NumberBase.twosComplement(v, _bits);

    return ToolScaffold(
      tool: encodeTool('number_base'),
      scrollable: true,
      toolbar: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              style: TextStyles.mono.copyWith(fontSize: 16, color: c.text),
              decoration: InputDecoration(
                hintText: '0xFF · 0b1010 · 42',
                errorText: _error,
                prefixIcon: Icon(Icons.onetwothree_rounded, color: c.textSubtle),
              ),
            ),
          ),
          const SizedBox(width: Space.md),
          Segmented<int>(
            expand: false,
            value: _radix,
            onChanged: (r) {
              final keep = _value;
              setState(() => _radix = r);
              if (keep != null) {
                _input.text = NumberBase.format(keep, r);
              } else {
                _parse();
              }
            },
            items: const [ChoiceItem(2, 'BIN'), ChoiceItem(8, 'OCT'), ChoiceItem(10, 'DEC'), ChoiceItem(16, 'HEX')],
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pane(
            title: 'number_base.results'.tr(),
            shrinkWrap: true,
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [for (final (k, s) in rows) ValueRow(label: k, value: s)],
            ),
          ),
          const SizedBox(height: Space.lg),
          Pane(
            title: 'number_base.bits'.tr(),
            headerExtra: Segmented<int>(
              expand: false,
              dense: true,
              value: _bits,
              onChanged: (b) => setState(() => _bits = b),
              items: const [ChoiceItem(8, '8'), ChoiceItem(16, '16'), ChoiceItem(32, '32'), ChoiceItem(64, '64')],
            ),
            shrinkWrap: true,
            padding: const EdgeInsets.all(Space.md),
            child: bits == null
                ? Center(
                    child: Text(
                      v == null ? '' : 'number_base.too_big'.tr(namedArgs: {'bits': '$_bits'}),
                      style: TextStyles.body.copyWith(color: c.textSubtle),
                    ),
                  )
                : _BitGrid(
                    bits: bits,
                    onToggle: (i) {
                      final chars = bits.split('');
                      chars[i] = chars[i] == '1' ? '0' : '1';
                      var nv = BigInt.parse(chars.join(), radix: 2);
                      // Interpret as signed when the top bit is set and the input was negative.
                      if (v!.isNegative && chars.first == '1') nv -= BigInt.one << _bits;
                      _setValue(nv);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _BitGrid extends StatelessWidget {
  const _BitGrid({required this.bits, required this.onToggle});
  final String bits;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bytes = bits.length ~/ 8;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var b = 0; b < bytes; b++)
          Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = b * 8; i < b * 8 + 8; i++)
                    GestureDetector(
                      onTap: () => onToggle(i),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Container(
                          width: 22,
                          height: 28,
                          margin: const EdgeInsets.only(right: 2),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: bits[i] == '1' ? c.accent : c.surfaceAlt,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            bits[i],
                            style: TextStyles.mono.copyWith(
                              fontSize: 12,
                              color: bits[i] == '1' ? c.onAccent : c.textSubtle,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '${bits.length - b * 8 - 1}…${bits.length - b * 8 - 8}',
                style: TextStyles.caption.copyWith(color: c.textSubtle, fontSize: 10),
              ),
            ],
          ),
      ],
    );
  }
}

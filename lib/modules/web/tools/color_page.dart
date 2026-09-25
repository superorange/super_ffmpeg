import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/feedback.dart';
import '../../../ui/widgets/workbench.dart';
import '../logic/color_tools.dart';
import '../web_module.dart';

/// Colour picker + converter with contrast checks and a tint/shade scale.
class ColorPage extends StatefulWidget {
  const ColorPage({super.key});

  @override
  State<ColorPage> createState() => _ColorPageState();
}

class _ColorPageState extends State<ColorPage> {
  final _input = TextEditingController(text: '#7C6CFF');
  double _h = 247, _s = 0.58, _v = 1, _a = 1;
  bool _invalid = false;

  Color get _color => ColorTools.fromHsv(_h, _s, _v, _a);

  @override
  void initState() {
    super.initState();
    _apply(ColorTools.parse(_input.text)!, updateField: false);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _apply(Color c, {bool updateField = true}) {
    final (h, s, v) = ColorTools.toHsv(c);
    setState(() {
      // Keep hue when the colour is grey so the picker doesn't jump.
      if (s > 0 && v > 0) _h = h;
      _s = s;
      _v = v;
      _a = c.a;
      _invalid = false;
    });
    if (updateField) _input.text = ColorTools.hex(c);
  }

  void _fromPicker({double? h, double? s, double? v, double? a}) {
    setState(() {
      _h = h ?? _h;
      _s = s ?? _s;
      _v = v ?? _v;
      _a = a ?? _a;
      _invalid = false;
    });
    _input.text = ColorTools.hex(_color);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = _color;
    final opaque = color.withValues(alpha: 1);
    final values = [
      ('HEX', ColorTools.hex(color)),
      ('RGB', ColorTools.rgb(color)),
      ('HSL', ColorTools.hsl(color)),
      ('HSV', ColorTools.hsv(color)),
      ('CMYK', ColorTools.cmyk(color)),
      ('Flutter', ColorTools.flutter(color)),
      ('CSS var', '--color: ${ColorTools.hex(color).toLowerCase()};'),
    ];

    final picker = Pane(
      title: 'color.picker'.tr(),
      icon: Icons.colorize_rounded,
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _SvSquare(
              hue: _h,
              s: _s,
              v: _v,
              onChanged: (s, v) => _fromPicker(s: s, v: v),
            ),
          ),
          const SizedBox(height: Space.md),
          _GradientSlider(
            value: _h / 360,
            colors: [for (var i = 0; i <= 6; i++) ColorTools.fromHsv(i * 60.0, 1, 1)],
            onChanged: (x) => _fromPicker(h: x * 360),
          ),
          const SizedBox(height: Space.sm),
          _GradientSlider(
            value: _a,
            checker: true,
            colors: [opaque.withValues(alpha: 0), opaque],
            onChanged: (x) => _fromPicker(a: (x * 100).round() / 100),
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Container(
                width: 44,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(Radii.control),
                  border: Border.all(color: c.border),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: TextField(
                  controller: _input,
                  style: TextStyles.mono.copyWith(color: c.text),
                  decoration: InputDecoration(
                    hintText: '#RRGGBB · rgb() · hsl() · tomato',
                    errorText: _invalid ? 'color.invalid'.tr() : null,
                  ),
                  onChanged: (t) {
                    final parsed = ColorTools.parse(t);
                    if (parsed == null) {
                      setState(() => _invalid = t.trim().isNotEmpty);
                    } else {
                      _apply(parsed, updateField: false);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final onWhite = ColorTools.contrast(opaque, const Color(0xFFFFFFFF));
    final onBlack = ColorTools.contrast(opaque, const Color(0xFF000000));
    final scale = ColorTools.scale(opaque);

    final info = ListView(
      children: [
        Pane(
          title: 'color.formats'.tr(),
          icon: Icons.tag_rounded,
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [for (final (k, v) in values) ValueRow(label: k, value: v)],
          ),
        ).shrink(),
        const SizedBox(height: Space.md),
        Pane(
          title: 'color.contrast'.tr(),
          icon: Icons.contrast_rounded,
          padding: const EdgeInsets.all(Space.md),
          child: Row(
            children: [
              Expanded(
                child: _ContrastCard(fg: opaque, bg: Colors.white, ratio: onWhite),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: _ContrastCard(fg: opaque, bg: Colors.black, ratio: onBlack),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: _ContrastCard(
                  fg: onWhite > onBlack ? Colors.white : Colors.black,
                  bg: opaque,
                  ratio: onWhite > onBlack ? onWhite : onBlack,
                ),
              ),
            ],
          ),
        ).shrink(),
        const SizedBox(height: Space.md),
        Pane(
          title: 'color.scale'.tr(),
          icon: Icons.gradient_rounded,
          padding: const EdgeInsets.all(Space.md),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                for (final s in scale)
                  Expanded(
                    child: Tooltip(
                      message: ColorTools.hex(s),
                      child: GestureDetector(
                        onTap: () => _apply(s),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: s,
                              borderRadius: BorderRadius.circular(6),
                              border: s == opaque ? Border.all(color: c.text, width: 2) : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ).shrink(),
      ],
    );

    return ToolScaffold(
      tool: webTool('color'),
      body: SplitPane(initial: 0.4, minExtent: 300, first: picker, second: info),
    );
  }
}

extension on Pane {
  Pane shrink() => Pane(
    title: title,
    icon: icon,
    padding: padding,
    shrinkWrap: true,
    child: child,
  );
}

class _ContrastCard extends StatelessWidget {
  const _ContrastCard({required this.fg, required this.bg, required this.ratio});
  final Color fg;
  final Color bg;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final aa = ratio >= 4.5, aaa = ratio >= 7, large = ratio >= 3;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Aa  ${ratio.toStringAsFixed(2)}:1', style: TextStyles.heading.copyWith(color: fg, fontSize: 16)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              Tag('AA', color: aa ? c.success : c.danger, icon: aa ? Icons.check_rounded : Icons.close_rounded),
              Tag('AAA', color: aaa ? c.success : c.danger, icon: aaa ? Icons.check_rounded : Icons.close_rounded),
              Tag('Large', color: large ? c.success : c.danger),
            ],
          ),
        ],
      ),
    );
  }
}

class _SvSquare extends StatelessWidget {
  const _SvSquare({required this.hue, required this.s, required this.v, required this.onChanged});
  final double hue;
  final double s;
  final double v;
  final void Function(double s, double v) onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        void update(Offset p) => onChanged(
          (p.dx / box.maxWidth).clamp(0.0, 1.0),
          1 - (p.dy / box.maxHeight).clamp(0.0, 1.0),
        );
        return GestureDetector(
          onPanDown: (d) => update(d.localPosition),
          onPanUpdate: (d) => update(d.localPosition),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.control),
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: ColorTools.fromHsv(hue, 1, 1))),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Colors.white, Color(0x00FFFFFF)]),
                    ),
                  ),
                ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Colors.black],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: s * box.maxWidth - 9,
                  top: (1 - v) * box.maxHeight - 9,
                  child: IgnorePointer(
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ColorTools.fromHsv(hue, s, v),
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GradientSlider extends StatelessWidget {
  const _GradientSlider({required this.value, required this.colors, required this.onChanged, this.checker = false});
  final double value;
  final List<Color> colors;
  final ValueChanged<double> onChanged;
  final bool checker;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        void update(Offset p) => onChanged((p.dx / box.maxWidth).clamp(0.0, 1.0));
        return GestureDetector(
          onPanDown: (d) => update(d.localPosition),
          onPanUpdate: (d) => update(d.localPosition),
          child: SizedBox(
            height: 18,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (checker)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: CustomPaint(painter: _Checker()),
                    ),
                  ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      gradient: LinearGradient(colors: colors),
                    ),
                  ),
                ),
                Positioned(
                  left: value * box.maxWidth - 9,
                  top: 0,
                  child: IgnorePointer(
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Checker extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final a = Paint()..color = const Color(0xFFE5E5E5);
    final b = Paint()..color = Colors.white;
    const s = 6.0;
    for (var y = 0.0; y < size.height; y += s) {
      for (var x = 0.0; x < size.width; x += s) {
        canvas.drawRect(Rect.fromLTWH(x, y, s, s), ((x + y) / s).round().isEven ? a : b);
      }
    }
  }

  @override
  bool shouldRepaint(_Checker old) => false;
}

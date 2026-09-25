import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class ChoiceItem<T> {
  const ChoiceItem(this.value, this.label, {this.hint, this.enabled = true, this.icon});
  final T value;
  final String label;
  final String? hint;
  final bool enabled;
  final IconData? icon;
}

/// Pill segmented control for 2–6 mutually exclusive options.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.expand = true,
    this.dense = false,
  });

  final List<ChoiceItem<T>> items;
  final T value;
  final ValueChanged<T> onChanged;

  /// Fill the available width (options panels) or size to content (toolbars).
  final bool expand;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget seg(ChoiceItem<T> item) => _Segment(
      item: item,
      selected: item.value == value,
      dense: dense,
      onTap: item.enabled ? () => onChanged(item.value) : null,
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.control + 2),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final item in items) expand ? Expanded(child: seg(item)) : seg(item),
        ],
      ),
    );
  }
}

class _Segment<T> extends StatefulWidget {
  const _Segment({required this.item, required this.selected, this.onTap, this.dense = false});
  final ChoiceItem<T> item;
  final bool selected;
  final bool dense;
  final VoidCallback? onTap;

  @override
  State<_Segment<T>> createState() => _SegmentState<T>();
}

class _SegmentState<T> extends State<_Segment<T>> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.onTap != null;
    final fg = widget.selected ? c.text : (enabled ? c.textMuted : c.textSubtle.withValues(alpha: 0.6));
    final body = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: widget.dense ? 24 : 28,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: widget.dense ? 9 : 10),
          decoration: BoxDecoration(
            color: widget.selected ? c.elevated : (_hover && enabled ? c.hover : Colors.transparent),
            borderRadius: BorderRadius.circular(Radii.control - 2),
            boxShadow: widget.selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: c.isDark ? 0.3 : 0.08),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
            border: widget.selected ? Border.all(color: c.borderStrong.withValues(alpha: c.isDark ? 0.8 : 0.5)) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.item.icon != null) ...[
                Icon(widget.item.icon, size: 14, color: fg),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  widget.item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyles.label.copyWith(
                    color: fg,
                    fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      selected: widget.selected,
      button: true,
      label: widget.item.label,
      child: widget.item.hint == null ? body : Tooltip(message: widget.item.hint!, child: body),
    );
  }
}

/// Wrapping chips for longer option lists.
class ChoiceChips<T> extends StatelessWidget {
  const ChoiceChips({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  final List<ChoiceItem<T>> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final item in items)
          SelectableChip(
            label: item.label,
            tooltip: item.hint,
            icon: item.icon,
            selected: item.value == value,
            onTap: item.enabled ? () => onChanged(item.value) : null,
          ),
      ],
    );
  }
}

class SelectableChip extends StatefulWidget {
  const SelectableChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.tooltip,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final String? tooltip;
  final IconData? icon;

  @override
  State<SelectableChip> createState() => _SelectableChipState();
}

class _SelectableChipState extends State<SelectableChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.onTap != null;
    final fg = widget.selected ? c.accent : (enabled ? c.text : c.textSubtle);
    final chip = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: widget.selected ? c.accentSoft : (_hover && enabled ? c.hover : c.surfaceAlt),
            borderRadius: BorderRadius.circular(Radii.control),
            border: Border.all(color: widget.selected ? c.accent.withValues(alpha: 0.6) : c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 14, color: fg),
                const SizedBox(width: 5),
              ],
              Text(
                widget.label,
                style: TextStyles.label.copyWith(
                  color: enabled ? fg : c.textSubtle.withValues(alpha: 0.6),
                  decoration: enabled ? null : TextDecoration.lineThrough,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      selected: widget.selected,
      button: true,
      child: widget.tooltip == null ? chip : Tooltip(message: widget.tooltip!, child: chip),
    );
  }
}

/// Slider with the current value shown on the right.
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.format,
    this.divisions,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: Space.md),
        Container(
          constraints: const BoxConstraints(minWidth: 56),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(Radii.control),
            border: Border.all(color: c.border),
          ),
          child: Text(
            format(value),
            textAlign: TextAlign.center,
            style: TextStyles.label.copyWith(color: c.text, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
      ],
    );
  }
}

/// Compact switch sized for desktop density.
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: FittedBox(
        child: Switch(value: value, onChanged: onChanged),
      ),
    );
  }
}

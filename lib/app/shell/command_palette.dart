import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/toolbox/tool.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/feedback.dart';
import '../tool_registry.dart';

class _Entry {
  const _Entry({required this.icon, required this.title, required this.color, this.subtitle, this.route, this.tool});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final String? route;
  final ToolDefinition? tool;
  bool get enabled => route != null;
}

/// ⌘K launcher: fuzzy-ish search across every registered tool and page.
class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => const CommandPalette(),
    );
  }

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  int _index = 0;

  List<_Entry> _results() {
    final q = _query.text;
    final pages = [
      _Entry(icon: Icons.space_dashboard_outlined, title: 'nav.home'.tr(), route: '/', color: context.colors.textMuted),
      _Entry(icon: Icons.layers_outlined, title: 'nav.tasks'.tr(), route: '/tasks', color: context.colors.textMuted),
      _Entry(
        icon: Icons.settings_outlined,
        title: 'nav.settings'.tr(),
        route: '/settings',
        color: context.colors.textMuted,
      ),
    ].where((e) => q.isEmpty || e.title.toLowerCase().contains(q.toLowerCase()));
    final tools = searchTools(toolRegistry, q, translate: (k) => k.tr());
    return [
      for (final t in tools)
        _Entry(
          icon: t.icon,
          title: t.nameKey.tr(),
          subtitle: t.descKey.tr(),
          color: t.category.color,
          route: t.isAvailable ? t.route : null,
          tool: t,
        ),
      ...pages,
    ];
  }

  void _open(_Entry e) {
    if (!e.enabled) return;
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(e.route!);
  }

  void _move(int delta, int count) {
    if (count == 0) return;
    setState(() => _index = (_index + delta) % count);
    const rowHeight = 52.0;
    final target = _index * rowHeight;
    if (_scroll.hasClients) {
      final pos = _scroll.position;
      if (target < pos.pixels) {
        _scroll.jumpTo(target);
      } else if (target + rowHeight > pos.pixels + pos.viewportDimension) {
        _scroll.jumpTo(target + rowHeight - pos.viewportDimension);
      }
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final results = _results();
    if (_index >= results.length) _index = 0;

    return Align(
      alignment: const Alignment(0, -0.45),
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 600,
          constraints: const BoxConstraints(maxHeight: 460),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(Radii.panel),
            border: Border.all(color: c.borderStrong),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 40, offset: const Offset(0, 16)),
            ],
          ),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1, results.length),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1, results.length),
              const SingleActivator(LogicalKeyboardKey.enter): () {
                if (results.isNotEmpty) _open(results[_index]);
              },
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, size: 20, color: c.textSubtle),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: TextField(
                          controller: _query,
                          autofocus: true,
                          onChanged: (_) => setState(() => _index = 0),
                          style: TextStyles.heading.copyWith(color: c.text, fontWeight: FontWeight.w400),
                          decoration: InputDecoration(
                            hintText: 'palette.hint'.tr(),
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ),
                      Text('esc', style: TextStyles.caption.copyWith(color: c.textSubtle)),
                    ],
                  ),
                ),
                Divider(color: c.border),
                Flexible(
                  child: results.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(Space.xxl),
                          child: Text('palette.empty'.tr(), style: TextStyles.body.copyWith(color: c.textMuted)),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(6),
                          itemCount: results.length,
                          itemExtent: 52,
                          itemBuilder: (_, i) => _ResultRow(
                            entry: results[i],
                            active: i == _index,
                            onHover: () => setState(() => _index = i),
                            onTap: () => _open(results[i]),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.entry, required this.active, required this.onHover, required this.onTap});
  final _Entry entry;
  final bool active;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = entry;
    return MouseRegion(
      onHover: (_) => onHover(),
      cursor: e.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active ? c.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.card - 2),
          ),
          child: Row(
            children: [
              ToolIcon(icon: e.icon, color: e.color, size: 30, muted: !e.enabled),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      style: TextStyles.body.copyWith(
                        color: e.enabled ? c.text : c.textSubtle,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (e.subtitle != null)
                      Text(
                        e.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyles.caption.copyWith(color: c.textSubtle),
                      ),
                  ],
                ),
              ),
              if (e.tool != null && !e.enabled) Tag('home.soon'.tr()),
              if (e.tool != null && e.enabled) Tag(e.tool!.category.labelKey.tr()),
              if (active && e.enabled) ...[
                const SizedBox(width: 6),
                Icon(Icons.keyboard_return_rounded, size: 14, color: c.textSubtle),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

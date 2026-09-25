import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/code_area.dart';
import '../../../ui/widgets/workbench.dart';

/// Collapsible tree for browsing a parsed JSON value.
class JsonTreeView extends StatefulWidget {
  const JsonTreeView({super.key, required this.value, this.initialDepth = 2});
  final Object? value;
  final int initialDepth;

  @override
  State<JsonTreeView> createState() => JsonTreeViewState();
}

class _Node {
  _Node(this.depth, this.key, this.value, this.path, {this.last = true});
  final int depth;
  final String? key;
  final Object? value;
  final String path;
  final bool last;
  bool get container => value is Map || value is List;
}

class JsonTreeViewState extends State<JsonTreeView> {
  final _collapsed = <String>{};
  final _expanded = <String>{};
  Object? _for;

  void expandAll() => setState(() {
    _collapsed.clear();
    _expanded.clear();
    _expandDeep = true;
  });

  void collapseAll() => setState(() {
    _expanded.clear();
    _collapsed.clear();
    _expandDeep = false;
    _collapsed.add(r'$');
  });

  bool _expandDeep = false;

  bool _isOpen(_Node n) {
    if (_collapsed.contains(n.path)) return false;
    if (_expanded.contains(n.path) || _expandDeep) return true;
    return n.depth < widget.initialDepth;
  }

  List<_Node> _flatten() {
    final out = <_Node>[];
    void walk(String? key, Object? v, int depth, String path, bool last) {
      final node = _Node(depth, key, v, path, last: last);
      out.add(node);
      if (!node.container || !_isOpen(node)) return;
      if (v is Map) {
        final keys = v.keys.toList();
        for (var i = 0; i < keys.length; i++) {
          final k = '${keys[i]}';
          final p = RegExp(r'^[A-Za-z_$][\w$]*$').hasMatch(k) ? '$path.$k' : '$path[${jsonEncode(k)}]';
          walk(k, v[keys[i]], depth + 1, p, i == keys.length - 1);
        }
      } else if (v is List) {
        for (var i = 0; i < v.length; i++) {
          walk('$i', v[i], depth + 1, '$path[$i]', i == v.length - 1);
        }
      }
    }

    walk(null, widget.value, 0, r'$', true);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (!identical(_for, widget.value)) {
      _for = widget.value;
    }
    final nodes = _flatten();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: nodes.length,
      itemExtent: 24,
      itemBuilder: (context, i) => _Row(
        node: nodes[i],
        open: nodes[i].container && _isOpen(nodes[i]),
        onToggle: () => setState(() {
          final n = nodes[i];
          if (_isOpen(n)) {
            _expanded.remove(n.path);
            _collapsed.add(n.path);
          } else {
            _collapsed.remove(n.path);
            _expanded.add(n.path);
          }
        }),
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({required this.node, required this.open, required this.onToggle});
  final _Node node;
  final bool open;
  final VoidCallback onToggle;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = codeThemeFor(c);
    final n = widget.node;
    final v = n.value;
    final mono = TextStyles.mono.copyWith(fontSize: 12.5, height: 1.2);
    TextStyle color(String k) => mono.copyWith(color: theme[k]?.color ?? c.text);

    final valueSpan = switch (v) {
      Map() => TextSpan(
        text: widget.open ? '{' : '{ ${v.length} }',
        style: mono.copyWith(color: c.textSubtle),
      ),
      List() => TextSpan(
        text: widget.open ? '[' : '[ ${v.length} ]',
        style: mono.copyWith(color: c.textSubtle),
      ),
      String() => TextSpan(text: jsonEncode(v), style: color('string')),
      num() => TextSpan(text: '$v', style: color('number')),
      bool() => TextSpan(text: '$v', style: color('literal')),
      null => TextSpan(text: 'null', style: color('literal')),
      _ => TextSpan(text: '$v', style: mono),
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: n.container ? widget.onToggle : null,
        child: Container(
          color: _hover ? c.hover.withValues(alpha: 0.5) : Colors.transparent,
          padding: EdgeInsets.only(left: 10.0 + n.depth * 18, right: 6),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: n.container
                    ? AnimatedRotation(
                        turns: widget.open ? 0.25 : 0,
                        duration: Motion.fast,
                        child: Icon(Icons.chevron_right_rounded, size: 15, color: c.textSubtle),
                      )
                    : null,
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      if (n.key != null) ...[
                        TextSpan(
                          text: int.tryParse(n.key!) != null && n.path.endsWith(']') ? n.key : '"${n.key}"',
                          style: int.tryParse(n.key!) != null && n.path.endsWith(']')
                              ? mono.copyWith(color: c.textSubtle)
                              : color('attr'),
                        ),
                        TextSpan(
                          text: ': ',
                          style: mono.copyWith(color: c.textSubtle),
                        ),
                      ],
                      valueSpan,
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_hover) ...[
                Tooltip(
                  message: n.path,
                  child: PaneAction(
                    icon: Icons.route_rounded,
                    tooltip: 'json.copy_path'.tr(),
                    onPressed: () => CopyAction.copy(context, n.path),
                  ),
                ),
                PaneAction(
                  icon: Icons.copy_rounded,
                  tooltip: 'json.copy_value'.tr(),
                  onPressed: () => CopyAction.copy(
                    context,
                    v is String ? v : const JsonEncoder.withIndent('  ').convert(v),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

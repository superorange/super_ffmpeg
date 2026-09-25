import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';

/// One console line.
class ConsoleEntry {
  const ConsoleEntry(this.level, this.text, {this.result = false});
  final String level;
  final String text;

  /// Final value of a script run (shown with a return arrow).
  final bool result;
}

/// Browser-devtools-like console list.
class ConsoleView extends StatelessWidget {
  const ConsoleView({super.key, required this.entries, this.empty, this.controller});
  final List<ConsoleEntry> entries;
  final Widget? empty;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (entries.isEmpty && empty != null) return empty!;
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        final (Color fg, Color? bg, IconData? icon) = switch (e.level) {
          'error' => (c.danger, c.danger.withValues(alpha: 0.08), Icons.cancel_rounded),
          'warn' => (c.warning, c.warning.withValues(alpha: 0.08), Icons.warning_rounded),
          'info' => (c.info, null, Icons.info_rounded),
          'debug' => (c.textSubtle, null, null),
          _ => (c.text, null, null),
        };
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
          decoration: BoxDecoration(
            color: bg,
            border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.6))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 18,
                child: e.result
                    ? Icon(Icons.keyboard_return_rounded, size: 13, color: c.textSubtle)
                    : icon == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(icon, size: 12, color: fg),
                      ),
              ),
              Expanded(
                child: SelectableText(
                  e.text,
                  style: TextStyles.mono.copyWith(
                    fontSize: 12,
                    color: e.result ? c.accent : fg,
                    fontWeight: e.result ? FontWeight.w600 : null,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

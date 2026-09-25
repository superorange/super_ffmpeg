import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../logic/diff.dart';

/// Side-by-side diff with line numbers and word-level highlights inside
/// modified lines.
class DiffView extends StatelessWidget {
  const DiffView({super.key, required this.result, this.onlyChanges = false, this.context = 3});
  final TextDiffResult result;

  /// Collapse unchanged runs, keeping [context] lines around each change.
  final bool onlyChanges;
  final int context;

  List<DiffRow?> _visible() {
    if (!onlyChanges) return result.rows;
    final rows = result.rows;
    final keep = List<bool>.filled(rows.length, false);
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].changed) {
        for (var j = (i - context).clamp(0, rows.length); j <= (i + context).clamp(0, rows.length - 1); j++) {
          keep[j] = true;
        }
      }
    }
    final out = <DiffRow?>[];
    for (var i = 0; i < rows.length; i++) {
      if (keep[i]) {
        out.add(rows[i]);
      } else if (out.isEmpty || out.last != null) {
        out.add(null); // gap marker
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible();
    return LayoutBuilder(
      builder: (context, box) {
        final half = (box.maxWidth - 1) / 2;
        return ListView.builder(
          itemCount: rows.length,
          itemExtent: 22,
          itemBuilder: (context, i) {
            final row = rows[i];
            if (row == null) return const _Gap();
            return Row(
              children: [
                SizedBox(
                  width: half,
                  child: _Side(row: row, left: true),
                ),
                Container(width: 1, color: context.colors.border),
                SizedBox(
                  width: half,
                  child: _Side(row: row, left: false),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Gap extends StatelessWidget {
  const _Gap();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      color: c.surfaceAlt.withValues(alpha: 0.6),
      alignment: Alignment.center,
      child: Icon(Icons.more_horiz_rounded, size: 14, color: c.textSubtle),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.row, required this.left});
  final DiffRow row;
  final bool left;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = left ? row.left : row.right;
    final no = left ? row.leftNo : row.rightNo;
    final removed = c.danger;
    final added = c.success;
    final tone = left ? removed : added;
    final Color? bg = switch (row.kind) {
      DiffOp.equal => null,
      DiffOp.delete => left ? removed.withValues(alpha: 0.12) : c.surfaceAlt.withValues(alpha: 0.5),
      DiffOp.insert => left ? c.surfaceAlt.withValues(alpha: 0.5) : added.withValues(alpha: 0.12),
      null => tone.withValues(alpha: 0.08),
    };
    final mono = TextStyles.mono.copyWith(fontSize: 12, height: 1.2, color: c.text);

    InlineSpan content() {
      if (text == null) return const TextSpan(text: '');
      if (row.kind != null) return TextSpan(text: text, style: mono);
      // Modified line: highlight the changed words.
      final segs = diffChars(row.left!, row.right!);
      return TextSpan(
        children: [
          for (final (op, s) in segs)
            if (op == DiffOp.equal)
              TextSpan(text: s, style: mono)
            else if ((op == DiffOp.delete) == left)
              TextSpan(
                text: s,
                style: mono.copyWith(backgroundColor: tone.withValues(alpha: 0.32)),
              ),
        ],
      );
    }

    return Container(
      color: bg,
      child: Row(
        children: [
          Container(
            width: 44,
            padding: const EdgeInsets.only(right: 8),
            alignment: Alignment.centerRight,
            child: Text(
              no == null ? '' : '$no',
              style: mono.copyWith(color: c.textSubtle.withValues(alpha: 0.7), fontSize: 11),
            ),
          ),
          SizedBox(
            width: 14,
            child: Text(
              row.kind == DiffOp.equal || text == null ? '' : (left ? '−' : '+'),
              style: mono.copyWith(color: tone, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text.rich(content(), maxLines: 1, overflow: TextOverflow.clip, softWrap: false),
          ),
        ],
      ),
    );
  }
}

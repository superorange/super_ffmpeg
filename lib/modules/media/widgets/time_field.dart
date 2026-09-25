import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../../../ui/theme/tokens.dart';

/// Text field for `hh:mm:ss.mmm` timecodes. Commits on submit / focus loss;
/// invalid input reverts to the last good value.
class TimecodeField extends StatefulWidget {
  const TimecodeField({
    super.key,
    required this.value,
    required this.onChanged,
    this.max,
    this.label,
  });

  final Duration value;
  final ValueChanged<Duration> onChanged;
  final Duration? max;
  final String? label;

  @override
  State<TimecodeField> createState() => _TimecodeFieldState();
}

class _TimecodeFieldState extends State<TimecodeField> {
  late final _controller = TextEditingController(text: Fmt.timecode(widget.value));
  final _focus = FocusNode();
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(TimecodeField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.value != widget.value) {
      _controller.text = Fmt.timecode(widget.value);
    }
  }

  void _commit() {
    var parsed = Fmt.parseTimecode(_controller.text);
    if (parsed == null) {
      setState(() => _invalid = true);
      return;
    }
    if (widget.max != null && parsed > widget.max!) parsed = widget.max!;
    setState(() => _invalid = false);
    _controller.text = Fmt.timecode(parsed);
    widget.onChanged(parsed);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextField(
      controller: _controller,
      focusNode: _focus,
      onSubmitted: (_) => _commit(),
      style: TextStyles.mono.copyWith(color: c.text, fontSize: 13),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: TextStyles.label.copyWith(color: c.textSubtle),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        errorText: _invalid ? '00:01:30.5' : null,
        prefixIcon: Icon(Icons.schedule_rounded, size: 15, color: c.textSubtle),
        prefixIconConstraints: const BoxConstraints(minWidth: 32),
      ),
    );
  }
}

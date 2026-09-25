import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../ui/widgets/buttons.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/workbench.dart';
import '../encode_module.dart';
import '../logic/codecs.dart';

/// Live two-way text encoder (URL, HTML entities, Unicode, hex, binary…).
class EncodePage extends StatefulWidget {
  const EncodePage({super.key, this.initial = TextCodec.urlComponent, this.codecs});
  final TextCodec initial;
  final List<TextCodec>? codecs;

  @override
  State<EncodePage> createState() => _EncodePageState();
}

class _EncodePageState extends State<EncodePage> {
  final _input = TextEditingController(text: 'https://example.com/搜索?q=super toolbox&lang=zh-CN');
  final _output = TextEditingController();
  late var _codec = widget.initial;
  var _decode = false;
  String? _error;

  static const _labels = {
    TextCodec.urlComponent: 'URL Component',
    TextCodec.url: 'URL',
    TextCodec.html: 'HTML Entity',
    TextCodec.unicode: 'Unicode \\u',
    TextCodec.hex: 'Hex',
    TextCodec.binary: 'Binary',
    TextCodec.base64: 'Base64',
    TextCodec.base64url: 'Base64URL',
  };

  @override
  void initState() {
    super.initState();
    _input.addListener(_run);
    _run();
  }

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    _error = null;
    var out = '';
    if (_input.text.isNotEmpty) {
      try {
        out = _decode ? Codecs.decode(_codec, _input.text) : Codecs.encode(_codec, _input.text);
      } catch (e) {
        _error = e is FormatException ? e.message : e.toString();
      }
    }
    _output.text = out;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final codecs =
        widget.codecs ??
        [TextCodec.urlComponent, TextCodec.url, TextCodec.html, TextCodec.unicode, TextCodec.hex, TextCodec.binary];
    return ToolScaffold(
      tool: encodeTool('encode'),
      toolbar: ToolbarRow(
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Segmented<bool>(
              expand: false,
              value: _decode,
              onChanged: (v) {
                setState(() => _decode = v);
                _run();
              },
              items: [
                ChoiceItem(false, 'encode.encode'.tr(), icon: Icons.lock_outline_rounded),
                ChoiceItem(true, 'encode.decode'.tr(), icon: Icons.lock_open_rounded),
              ],
            ),
            const SizedBox(width: 8),
            AppButton(
              label: 'common.swap'.tr(),
              icon: Icons.swap_horiz_rounded,
              size: ButtonSize.sm,
              onPressed: _error != null || _output.text.isEmpty
                  ? null
                  : () {
                      final out = _output.text;
                      setState(() => _decode = !_decode);
                      _input.text = out;
                    },
            ),
          ],
        ),
        children: [
          ChoiceChips<TextCodec>(
            value: _codec,
            onChanged: (v) {
              setState(() => _codec = v);
              _run();
            },
            items: [for (final c in codecs) ChoiceItem(c, _labels[c]!)],
          ),
        ],
      ),
      body: SplitPane(
        vertical: true,
        first: Pane(
          title: 'common.input'.tr(),
          actions: [
            PaneAction(
              icon: Icons.content_paste_rounded,
              tooltip: 'common.paste'.tr(),
              onPressed: () async => _input.text = await readClipboard() ?? _input.text,
            ),
            PaneAction(icon: Icons.backspace_outlined, tooltip: 'common.clear'.tr(), onPressed: _input.clear),
          ],
          footer: StatusLine('common.chars'.tr(namedArgs: {'n': '${_input.text.length}'})),
          child: TextArea(controller: _input),
        ),
        second: Pane(
          title: 'common.output'.tr(),
          actions: [CopyAction(text: () => _output.text)],
          footer: _error == null
              ? StatusLine('common.chars'.tr(namedArgs: {'n': '${_output.text.length}'}))
              : StatusLine(_error!, tone: StatusTone.danger),
          child: TextArea(controller: _output, readOnly: true),
        ),
      ),
    );
  }
}

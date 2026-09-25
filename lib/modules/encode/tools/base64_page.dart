import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/toolbox/file_intake.dart';
import '../../../core/utils/format.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/buttons.dart';
import '../../../ui/widgets/feedback.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/workbench.dart';
import '../encode_module.dart';
import '../logic/codecs.dart';

enum _Mode { text, file }

/// Base64 for text and files — with image preview and data-URI output.
class Base64Page extends StatefulWidget {
  const Base64Page({super.key});

  @override
  State<Base64Page> createState() => _Base64PageState();
}

class _Base64PageState extends State<Base64Page> with FileIntakeMixin {
  @override
  String get intakeId => 'base64';

  @override
  void onFiles(List<String> paths) => _loadFile(paths.first);

  var _mode = _Mode.text;

  // Text mode.
  final _plain = TextEditingController(text: 'Hello, Super Toolbox! 你好 👋');
  final _encoded = TextEditingController();
  var _urlSafe = false;
  String? _error;
  bool _syncing = false;

  // File mode.
  String? _fileName;
  Uint8List? _bytes;
  var _dataUri = true;

  @override
  void initState() {
    super.initState();
    _plain.addListener(_encode);
    _encoded.addListener(_decode);
    _encode();
  }

  @override
  void dispose() {
    _plain.dispose();
    _encoded.dispose();
    super.dispose();
  }

  void _encode() {
    if (_syncing) return;
    _syncing = true;
    _encoded.text = Codecs.encode(_urlSafe ? TextCodec.base64url : TextCodec.base64, _plain.text);
    _error = null;
    _syncing = false;
    setState(() {});
  }

  void _decode() {
    if (_syncing) return;
    _syncing = true;
    try {
      final bytes = Codecs.base64Decode(_encoded.text);
      final kind = Codecs.sniff(bytes);
      if (kind != null) {
        _error = null;
        _bytes = bytes;
        _fileName = 'decoded.${kind.ext}';
        _plain.text = '';
        _error = 'base64.binary_detected'.tr(namedArgs: {'type': kind.mime});
      } else {
        _plain.text = utf8.decode(bytes);
        _error = null;
      }
    } on FormatException catch (e) {
      _error = e.message;
    }
    _syncing = false;
    setState(() {});
  }

  Future<void> _loadFile(String path) async {
    final bytes = await File(path).readAsBytes();
    setState(() {
      _bytes = bytes;
      _fileName = p.basename(path);
      _mode = _Mode.file;
    });
  }

  String get _fileEncoded {
    if (_bytes == null) return '';
    final b64 = base64.encode(_bytes!);
    if (!_dataUri) return b64;
    final mime = Codecs.sniff(_bytes!)?.mime ?? 'application/octet-stream';
    return 'data:$mime;base64,$b64';
  }

  Future<void> _saveBytes() async {
    if (_bytes == null) return;
    final path = await FilePicker.platform.saveFile(fileName: _fileName ?? 'decoded.bin');
    if (path == null) return;
    await File(path).writeAsBytes(_bytes!);
    if (mounted) showToast(context, 'common.saved'.tr(namedArgs: {'path': path}));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = switch (_mode) {
      _Mode.text => SplitPane(
        vertical: true,
        first: Pane(
          title: 'base64.plain'.tr(),
          actions: [
            PaneAction(
              icon: Icons.content_paste_rounded,
              tooltip: 'common.paste'.tr(),
              onPressed: () async => _plain.text = await readClipboard() ?? _plain.text,
            ),
            CopyAction(text: () => _plain.text),
            PaneAction(icon: Icons.backspace_outlined, tooltip: 'common.clear'.tr(), onPressed: _plain.clear),
          ],
          footer: StatusLine('common.bytes'.tr(namedArgs: {'n': '${utf8.encode(_plain.text).length}'})),
          child: TextArea(controller: _plain),
        ),
        second: Pane(
          title: 'Base64',
          actions: [
            if (_bytes != null && _error != null && _plain.text.isEmpty)
              PaneAction(icon: Icons.save_alt_rounded, tooltip: 'common.save'.tr(), onPressed: _saveBytes),
            PaneAction(
              icon: Icons.content_paste_rounded,
              tooltip: 'common.paste'.tr(),
              onPressed: () async => _encoded.text = await readClipboard() ?? _encoded.text,
            ),
            CopyAction(text: () => _encoded.text),
            PaneAction(icon: Icons.backspace_outlined, tooltip: 'common.clear'.tr(), onPressed: _encoded.clear),
          ],
          footer: _error == null
              ? StatusLine('common.chars'.tr(namedArgs: {'n': '${_encoded.text.length}'}))
              : StatusLine(
                  _error!,
                  tone: _bytes != null && _plain.text.isEmpty ? StatusTone.warning : StatusTone.danger,
                ),
          child: TextArea(controller: _encoded),
        ),
      ),
      _Mode.file => SplitPane(
        initial: 0.4,
        first: Pane(
          title: 'base64.file'.tr(),
          icon: Icons.insert_drive_file_outlined,
          child: GestureDetector(
            onTap: () async {
              final r = await FilePicker.platform.pickFiles();
              final path = r?.files.single.path;
              if (path != null) await _loadFile(path);
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AnimatedContainer(
                duration: Motion.fast,
                margin: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  color: c.surfaceAlt.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(Radii.card),
                  border: Border.all(color: c.border),
                ),
                child: Center(
                  child: _bytes == null
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.upload_file_rounded, size: 36, color: c.textSubtle),
                            const SizedBox(height: 10),
                            Text('base64.drop'.tr(), style: TextStyles.heading.copyWith(color: c.text)),
                            const SizedBox(height: 4),
                            Text('base64.drop_hint'.tr(), style: TextStyles.caption.copyWith(color: c.textSubtle)),
                          ],
                        )
                      : Padding(
                          padding: const EdgeInsets.all(Space.lg),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (Codecs.sniff(_bytes!)?.mime.startsWith('image/') == true &&
                                  Codecs.sniff(_bytes!)?.ext != 'svg')
                                Flexible(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.memory(_bytes!, fit: BoxFit.contain),
                                  ),
                                )
                              else
                                Icon(Icons.description_outlined, size: 48, color: c.textSubtle),
                              const SizedBox(height: 12),
                              Text(_fileName ?? '', style: TextStyles.heading.copyWith(color: c.text)),
                              Text(
                                '${Fmt.bytes(_bytes!.length)} · ${Codecs.sniff(_bytes!)?.mime ?? 'binary'}',
                                style: TextStyles.caption.copyWith(color: c.textSubtle),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
        second: Pane(
          title: 'Base64',
          headerExtra: Segmented<bool>(
            expand: false,
            dense: true,
            value: _dataUri,
            onChanged: (v) => setState(() => _dataUri = v),
            items: const [ChoiceItem(true, 'Data URI'), ChoiceItem(false, 'Raw')],
          ),
          actions: [CopyAction(text: () => _fileEncoded)],
          footer: StatusLine(
            _bytes == null
                ? ''
                : '${'common.chars'.tr(namedArgs: {'n': '${_fileEncoded.length}'})}  ·  +${((_fileEncoded.length / _bytes!.length - 1) * 100).round()}%',
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              _fileEncoded.length > 200000
                  ? '${_fileEncoded.substring(0, 200000)}…\n\n${'base64.truncated'.tr()}'
                  : _fileEncoded,
              style: TextStyles.mono.copyWith(fontSize: 11.5, color: c.textMuted),
            ),
          ),
        ),
      ),
    };

    return ToolScaffold(
      tool: encodeTool('base64'),
      onFiles: onFiles,
      toolbar: ToolbarRow(
        trailing: _mode == _Mode.file && _bytes != null
            ? AppButton(
                label: 'common.save'.tr(),
                icon: Icons.save_alt_rounded,
                size: ButtonSize.sm,
                onPressed: _saveBytes,
              )
            : null,
        children: [
          Segmented<_Mode>(
            expand: false,
            value: _mode,
            onChanged: (v) => setState(() => _mode = v),
            items: [
              ChoiceItem(_Mode.text, 'base64.text'.tr(), icon: Icons.notes_rounded),
              ChoiceItem(_Mode.file, 'base64.file'.tr(), icon: Icons.image_outlined),
            ],
          ),
          if (_mode == _Mode.text)
            ToolbarField(
              label: 'base64.url_safe'.tr(),
              child: AppSwitch(
                value: _urlSafe,
                onChanged: (v) {
                  setState(() => _urlSafe = v);
                  _encode();
                },
              ),
            ),
        ],
      ),
      body: body,
    );
  }
}

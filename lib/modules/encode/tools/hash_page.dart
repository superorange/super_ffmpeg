import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/toolbox/file_intake.dart';
import '../../../core/utils/format.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/buttons.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/workbench.dart';
import '../encode_module.dart';
import '../logic/hashing.dart';

enum _Mode { text, file }

/// Digests for text or files, HMAC, and "does it match?" verification.
class HashPage extends StatefulWidget {
  const HashPage({super.key});

  @override
  State<HashPage> createState() => _HashPageState();
}

class _HashPageState extends State<HashPage> with FileIntakeMixin {
  @override
  String get intakeId => 'hash';

  @override
  void onFiles(List<String> paths) => _hashFile(paths.first);

  var _mode = _Mode.text;
  final _text = TextEditingController(text: 'Super Toolbox');
  final _key = TextEditingController();
  final _expected = TextEditingController();
  var _upper = false;

  String? _file;
  int _fileSize = 0;
  Map<HashAlg, String>? _fileHashes;
  double? _progress;

  @override
  void initState() {
    super.initState();
    for (final t in [_text, _key, _expected]) {
      t.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _key.dispose();
    _expected.dispose();
    super.dispose();
  }

  Future<void> _hashFile(String path) async {
    setState(() {
      _mode = _Mode.file;
      _file = path;
      _fileHashes = null;
      _progress = 0;
    });
    _fileSize = await File(path).length();
    final result = await Hashing.file(
      path,
      onProgress: (v) {
        if (mounted && _file == path) setState(() => _progress = v);
      },
    );
    if (mounted && _file == path) {
      setState(() {
        _fileHashes = result;
        _progress = null;
      });
    }
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles();
    final path = r?.files.single.path;
    if (path != null) await _hashFile(path);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final expected = _expected.text.trim().toLowerCase();
    final hmac = _key.text.isNotEmpty && _mode == _Mode.text;

    Map<HashAlg, String> values;
    if (_mode == _Mode.text) {
      values = {
        for (final a in HashAlg.values)
          if (!(hmac && a == HashAlg.crc32)) a: Hashing.text(a, _text.text, hmacKey: _key.text, upper: _upper),
      };
    } else {
      values = {
        for (final e in (_fileHashes ?? const <HashAlg, String>{}).entries)
          e.key: _upper ? e.value.toUpperCase() : e.value,
      };
    }
    final match = expected.isEmpty ? null : values.entries.where((e) => e.value.toLowerCase() == expected).firstOrNull;

    final source = _mode == _Mode.text
        ? Pane(
            title: 'common.input'.tr(),
            actions: [
              PaneAction(
                icon: Icons.content_paste_rounded,
                tooltip: 'common.paste'.tr(),
                onPressed: () async => _text.text = await readClipboard() ?? _text.text,
              ),
              PaneAction(icon: Icons.backspace_outlined, tooltip: 'common.clear'.tr(), onPressed: _text.clear),
            ],
            footer: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _key,
                    style: TextStyles.mono.copyWith(fontSize: 12, color: c.text),
                    decoration: InputDecoration(
                      hintText: 'hash.hmac_hint'.tr(),
                      prefixIcon: Icon(Icons.vpn_key_outlined, size: 15, color: c.textSubtle),
                      prefixIconConstraints: const BoxConstraints(minWidth: 30),
                    ),
                  ),
                ),
              ],
            ),
            child: TextArea(controller: _text),
          )
        : GestureDetector(
            onTap: _pick,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AnimatedContainer(
                duration: Motion.fast,
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(Radii.card),
                  border: Border.all(color: c.border),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _file == null ? Icons.upload_file_rounded : Icons.insert_drive_file_rounded,
                          size: 40,
                          color: _file == null ? c.textSubtle : c.accent,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _file == null ? 'hash.drop'.tr() : p.basename(_file!),
                          textAlign: TextAlign.center,
                          style: TextStyles.heading.copyWith(color: c.text),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _file == null ? 'hash.drop_hint'.tr() : Fmt.bytes(_fileSize),
                          style: TextStyles.caption.copyWith(color: c.textSubtle),
                        ),
                        if (_progress != null) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: 220,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(value: _progress, minHeight: 5),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );

    final results = Pane(
      title: hmac ? 'HMAC' : 'hash.digests'.tr(),
      icon: Icons.fingerprint_rounded,
      actions: [CopyAction(text: () => values.entries.map((e) => '${e.key.label}: ${e.value}').join('\n'))],
      footer: TextField(
        controller: _expected,
        style: TextStyles.mono.copyWith(fontSize: 12, color: c.text),
        decoration: InputDecoration(
          hintText: 'hash.verify_hint'.tr(),
          prefixIcon: Icon(
            match != null ? Icons.check_circle_rounded : (expected.isEmpty ? Icons.rule_rounded : Icons.cancel_rounded),
            size: 16,
            color: match != null ? c.success : (expected.isEmpty ? c.textSubtle : c.danger),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 32),
          helperText: expected.isEmpty
              ? null
              : match != null
              ? 'hash.match'.tr(namedArgs: {'alg': match.key.label})
              : 'hash.no_match'.tr(),
          helperStyle: TextStyles.caption.copyWith(color: match != null ? c.success : c.danger),
        ),
      ),
      padding: const EdgeInsets.all(6),
      child: ListView(
        children: [
          for (final e in values.entries)
            Container(
              decoration: BoxDecoration(
                color: match?.key == e.key ? c.success.withValues(alpha: 0.1) : null,
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: ValueRow(label: e.key.label, value: e.value),
            ),
        ],
      ),
    );

    return ToolScaffold(
      tool: encodeTool('hash'),
      onFiles: onFiles,
      toolbar: ToolbarRow(
        trailing: _mode == _Mode.file
            ? AppButton(
                label: 'hash.choose'.tr(),
                icon: Icons.folder_open_rounded,
                size: ButtonSize.sm,
                onPressed: _pick,
              )
            : null,
        children: [
          Segmented<_Mode>(
            expand: false,
            value: _mode,
            onChanged: (v) => setState(() => _mode = v),
            items: [
              ChoiceItem(_Mode.text, 'base64.text'.tr(), icon: Icons.notes_rounded),
              ChoiceItem(_Mode.file, 'base64.file'.tr(), icon: Icons.insert_drive_file_outlined),
            ],
          ),
          ToolbarField(
            label: 'hash.uppercase'.tr(),
            child: AppSwitch(value: _upper, onChanged: (v) => setState(() => _upper = v)),
          ),
        ],
      ),
      body: SplitPane(initial: 0.42, first: source, second: results),
    );
  }
}

import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'code_area.dart';
import 'feedback.dart';
import 'workbench.dart';

/// A [Pane] holding a [CodeArea] with the standard editor actions:
/// paste · open file · save · copy · clear.
class EditorPane extends StatelessWidget {
  const EditorPane({
    super.key,
    required this.controller,
    this.title,
    this.icon,
    this.language = CodeLang.plain,
    this.readOnly = false,
    this.hint,
    this.footer,
    this.headerExtra,
    this.extraActions = const [],
    this.paste = true,
    this.open = false,
    this.save = false,
    this.copy = true,
    this.clear = true,
    this.wordWrap = false,
    this.saveName = 'untitled.txt',
    this.openExtensions,
  });

  final CodeLineEditingController controller;
  final String? title;
  final IconData? icon;
  final CodeLang language;
  final bool readOnly;
  final String? hint;
  final Widget? footer;
  final Widget? headerExtra;
  final List<Widget> extraActions;
  final bool paste;
  final bool open;
  final bool save;
  final bool copy;
  final bool clear;
  final bool wordWrap;
  final String saveName;
  final List<String>? openExtensions;

  Future<void> _open(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: openExtensions == null ? FileType.any : FileType.custom,
      allowedExtensions: openExtensions,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    try {
      controller.text = await File(path).readAsString();
    } on FileSystemException catch (e) {
      if (context.mounted) showToast(context, e.message);
    } on FormatException {
      if (context.mounted) showToast(context, 'common.not_text'.tr());
    }
  }

  Future<void> _save(BuildContext context) async {
    final path = await FilePicker.platform.saveFile(fileName: saveName);
    if (path == null) return;
    await File(path).writeAsString(controller.text);
    if (context.mounted) showToast(context, 'common.saved'.tr(namedArgs: {'path': path}));
  }

  @override
  Widget build(BuildContext context) {
    return Pane(
      title: title,
      icon: icon,
      headerExtra: headerExtra,
      footer: footer,
      color: context.colors.codeBg,
      actions: [
        ...extraActions,
        if (paste && !readOnly)
          PaneAction(
            icon: Icons.content_paste_rounded,
            tooltip: 'common.paste'.tr(),
            onPressed: () async {
              final t = await readClipboard();
              if (t != null) controller.text = t;
            },
          ),
        if (open && !readOnly)
          PaneAction(icon: Icons.file_open_outlined, tooltip: 'common.open_file'.tr(), onPressed: () => _open(context)),
        if (save)
          PaneAction(icon: Icons.save_alt_rounded, tooltip: 'common.save'.tr(), onPressed: () => _save(context)),
        if (copy) CopyAction(text: () => controller.text),
        if (clear && !readOnly)
          PaneAction(
            icon: Icons.backspace_outlined,
            tooltip: 'common.clear'.tr(),
            onPressed: () => controller.text = '',
          ),
      ],
      child: CodeArea(
        controller: controller,
        language: language,
        readOnly: readOnly,
        hint: hint,
        wordWrap: wordWrap,
      ),
    );
  }
}

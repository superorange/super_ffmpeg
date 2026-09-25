import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';

import '../theme/tokens.dart';

export 'package:re_editor/re_editor.dart' show CodeLineEditingController, CodeLineEditingValue;

/// Languages the toolbox highlights.
enum CodeLang {
  plain(null),
  json('json'),
  yaml('yaml'),
  html('xml'),
  xml('xml'),
  css('css'),
  javascript('javascript'),
  typescript('typescript'),
  markdown('markdown'),
  sql('sql'),
  dart('dart'),
  go('go'),
  swift('swift'),
  kotlin('kotlin');

  const CodeLang(this.mode);
  final String? mode;

  Mode? get _grammar => switch (this) {
    json => langJson,
    yaml => langYaml,
    html || xml => langXml,
    css => langCss,
    javascript => langJavascript,
    typescript => langTypescript,
    markdown => langMarkdown,
    sql => langSql,
    dart => langDart,
    go => langGo,
    swift => langSwift,
    kotlin => langKotlin,
    plain => null,
  };
}

/// Syntax colours derived from the app palette so editors match the theme.
Map<String, TextStyle> codeThemeFor(AppColors c) {
  final dark = c.isDark;
  final keyword = dark ? const Color(0xFFC792EA) : const Color(0xFF8B2FC9);
  final string = dark ? const Color(0xFFA5D6A7) : const Color(0xFF1F8A3B);
  final number = dark ? const Color(0xFFF78C6C) : const Color(0xFFC2410C);
  final attr = dark ? const Color(0xFF82AAFF) : const Color(0xFF1D4ED8);
  final title = dark ? const Color(0xFFFFCB6B) : const Color(0xFFB45309);
  final tag = dark ? const Color(0xFFFF7A90) : const Color(0xFFBE123C);
  final comment = c.textSubtle;
  return {
    'root': TextStyle(color: c.text, backgroundColor: Colors.transparent),
    'comment': TextStyle(color: comment, fontStyle: FontStyle.italic),
    'quote': TextStyle(color: comment, fontStyle: FontStyle.italic),
    'doctag': TextStyle(color: keyword),
    'keyword': TextStyle(color: keyword),
    'formula': TextStyle(color: keyword),
    'section': TextStyle(color: title, fontWeight: FontWeight.w600),
    'name': TextStyle(color: tag),
    'selector-tag': TextStyle(color: tag),
    'deletion': TextStyle(color: c.danger),
    'subst': TextStyle(color: c.text),
    'literal': TextStyle(color: number),
    'string': TextStyle(color: string),
    'regexp': TextStyle(color: string),
    'addition': TextStyle(color: c.success),
    'attribute': TextStyle(color: attr),
    'meta-string': TextStyle(color: string),
    'attr': TextStyle(color: attr),
    'variable': TextStyle(color: tag),
    'template-variable': TextStyle(color: tag),
    'type': TextStyle(color: title),
    'selector-class': TextStyle(color: title),
    'selector-attr': TextStyle(color: title),
    'selector-pseudo': TextStyle(color: title),
    'number': TextStyle(color: number),
    'symbol': TextStyle(color: attr),
    'bullet': TextStyle(color: attr),
    'link': TextStyle(color: attr, decoration: TextDecoration.underline),
    'meta': TextStyle(color: comment),
    'selector-id': TextStyle(color: attr),
    'title': TextStyle(color: attr),
    'built_in': TextStyle(color: title),
    'class-title': TextStyle(color: title),
    'emphasis': const TextStyle(fontStyle: FontStyle.italic),
    'strong': const TextStyle(fontWeight: FontWeight.bold),
  };
}

/// Code/text editor with line numbers and highlighting (re_editor).
class CodeArea extends StatelessWidget {
  const CodeArea({
    super.key,
    required this.controller,
    this.language = CodeLang.plain,
    this.readOnly = false,
    this.hint,
    this.wordWrap = false,
    this.lineNumbers = true,
    this.onChanged,
    this.focusNode,
    this.fontSize = 12.5,
  });

  final CodeLineEditingController controller;
  final CodeLang language;
  final bool readOnly;
  final String? hint;
  final bool wordWrap;
  final bool lineNumbers;
  final ValueChanged<CodeLineEditingValue>? onChanged;
  final FocusNode? focusNode;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final grammar = language._grammar;
    final numberStyle = TextStyles.mono.copyWith(fontSize: fontSize - 1, color: c.textSubtle.withValues(alpha: 0.6));
    return CodeEditor(
      controller: controller,
      readOnly: readOnly,
      hint: hint,
      wordWrap: wordWrap,
      focusNode: focusNode,
      onChanged: onChanged,
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 24),
      verticalScrollbarWidth: 8,
      horizontalScrollbarHeight: 8,
      style: CodeEditorStyle(
        fontSize: fontSize,
        fontFamily: TextStyles.mono.fontFamily,
        fontFamilyFallback: TextStyles.mono.fontFamilyFallback,
        fontHeight: 1.55,
        textColor: c.text,
        hintTextColor: c.textSubtle,
        backgroundColor: Colors.transparent,
        selectionColor: c.accent.withValues(alpha: 0.28),
        highlightColor: c.warning.withValues(alpha: 0.28),
        cursorColor: c.accent,
        cursorLineColor: c.text.withValues(alpha: 0.035),
        chunkIndicatorColor: c.textSubtle,
        codeTheme: grammar == null
            ? null
            : CodeHighlightTheme(
                languages: {language.mode!: CodeHighlightThemeMode(mode: grammar)},
                theme: codeThemeFor(c),
              ),
      ),
      indicatorBuilder: lineNumbers
          ? (context, editingController, chunkController, notifier) => Padding(
              padding: const EdgeInsets.only(left: 6),
              child: DefaultCodeLineNumber(
                controller: editingController,
                notifier: notifier,
                textStyle: numberStyle,
                focusedTextStyle: numberStyle.copyWith(color: c.textMuted),
              ),
            )
          : null,
    );
  }
}

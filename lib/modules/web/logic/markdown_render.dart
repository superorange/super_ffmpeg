import 'package:markdown/markdown.dart' as md;

/// Markdown → standalone HTML page with GitHub-flavoured styling.
abstract final class MarkdownRender {
  static String body(String source) => md.markdownToHtml(
    source,
    extensionSet: md.ExtensionSet.gitHubWeb,
    inlineSyntaxes: [md.InlineHtmlSyntax()],
  );

  static String page(String source, {required bool dark, String title = 'Document'}) {
    final c = dark ? _dark : _light;
    return '''<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_escape(title)}</title>
<style>
:root { color-scheme: ${dark ? 'dark' : 'light'}; }
html { background: ${c['bg']}; }
body { margin: 0 auto; max-width: 860px; padding: 32px 40px 64px; color: ${c['text']}; background: ${c['bg']};
  font: 15px/1.7 -apple-system, BlinkMacSystemFont, "PingFang SC", "Segoe UI", Helvetica, Arial, sans-serif; }
h1, h2, h3, h4, h5, h6 { line-height: 1.3; margin: 1.6em 0 .6em; font-weight: 650; }
h1 { font-size: 2em; padding-bottom: .3em; border-bottom: 1px solid ${c['border']}; }
h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid ${c['border']}; }
h3 { font-size: 1.25em; }
body > :first-child { margin-top: 0; }
a { color: ${c['link']}; text-decoration: none; } a:hover { text-decoration: underline; }
p, ul, ol, blockquote, pre, table { margin: 0 0 1em; }
code { font: 13px/1.5 "SF Mono", Menlo, Consolas, monospace; background: ${c['code']}; padding: .15em .4em; border-radius: 6px; }
pre { background: ${c['code']}; padding: 14px 16px; border-radius: 10px; overflow: auto; border: 1px solid ${c['border']}; }
pre code { background: none; padding: 0; }
blockquote { margin-left: 0; padding: .2em 1em; color: ${c['muted']}; border-left: 4px solid ${c['accent']}; background: ${c['quote']}; border-radius: 0 8px 8px 0; }
table { border-collapse: collapse; display: block; overflow: auto; }
th, td { border: 1px solid ${c['border']}; padding: 6px 13px; }
th { background: ${c['code']}; font-weight: 600; }
tr:nth-child(2n) td { background: ${c['stripe']}; }
img { max-width: 100%; border-radius: 8px; }
hr { border: 0; height: 1px; background: ${c['border']}; margin: 2em 0; }
ul.contains-task-list, li.task-list-item { list-style: none; }
li.task-list-item input { margin: 0 .4em 0 -1.4em; }
mark { background: #fde68a; color: #111; }
kbd { font: 12px monospace; padding: 2px 6px; border: 1px solid ${c['border']}; border-bottom-width: 2px; border-radius: 5px; }
</style></head><body>
${body(source)}
</body></html>''';
  }

  static String _escape(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;');

  static const _light = {
    'bg': '#ffffff',
    'text': '#1f2328',
    'muted': '#59636e',
    'border': '#d1d9e0',
    'code': '#f3f4f7',
    'link': '#5a48ea',
    'accent': '#7c6cff',
    'quote': '#f7f6ff',
    'stripe': '#fafbfc',
  };
  static const _dark = {
    'bg': '#16161c',
    'text': '#e6e6ea',
    'muted': '#a3a3b2',
    'border': '#2c2c36',
    'code': '#1f1f27',
    'link': '#a99fff',
    'accent': '#7c6cff',
    'quote': '#1c1b2a',
    'stripe': '#191920',
  };
}

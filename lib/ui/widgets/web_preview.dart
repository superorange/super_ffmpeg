import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/tokens.dart';

/// Whether an embedded browser is available (WKWebView on macOS). Widget
/// tests override this to false.
final webPreviewSupportedProvider = Provider<bool>((ref) => Platform.isMacOS || Platform.isIOS || Platform.isAndroid);

/// Injected first into every previewed document: forwards console output
/// and uncaught errors to [WebPreview.onConsole].
const _consoleBridge = r'''
<script>
(function () {
  function fmt(v) {
    if (typeof v === 'string') return v;
    if (v instanceof Error) return v.name + ': ' + v.message;
    try { return JSON.stringify(v, null, 2); } catch (e) { return String(v); }
  }
  ['log', 'info', 'warn', 'error', 'debug'].forEach(function (level) {
    var orig = console[level];
    console[level] = function () {
      try { SuperToolbox.postMessage(JSON.stringify({ level: level, text: Array.prototype.map.call(arguments, fmt).join(' ') })); } catch (e) {}
      orig && orig.apply(console, arguments);
    };
  });
  window.addEventListener('error', function (e) {
    try { SuperToolbox.postMessage(JSON.stringify({ level: 'error', text: e.message + (e.lineno ? ' (line ' + e.lineno + ')' : '') })); } catch (x) {}
  });
  window.addEventListener('unhandledrejection', function (e) {
    try { SuperToolbox.postMessage(JSON.stringify({ level: 'error', text: 'Unhandled rejection: ' + fmt(e.reason) })); } catch (x) {}
  });
})();
</script>
''';

/// Live HTML preview in an embedded WebKit view. Reloads when [html] changes.
class WebPreview extends ConsumerStatefulWidget {
  const WebPreview({super.key, required this.html, this.onConsole, this.baseUrl});

  /// Complete document or fragment.
  final String html;
  final void Function(String level, String text)? onConsole;

  /// Resolves relative URLs (e.g. images next to a Markdown file).
  final String? baseUrl;

  @override
  ConsumerState<WebPreview> createState() => _WebPreviewState();
}

class _WebPreviewState extends ConsumerState<WebPreview> {
  WebViewController? _controller;
  String? _loaded;

  WebViewController _create() {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'SuperToolbox',
        onMessageReceived: (m) {
          try {
            final data = jsonDecode(m.message) as Map<String, dynamic>;
            widget.onConsole?.call('${data['level']}', '${data['text']}');
          } catch (_) {
            widget.onConsole?.call('log', m.message);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          // Links open in the preview only for in-page anchors.
          onNavigationRequest: (r) => r.url.startsWith('about:') || r.url.startsWith('data:') || r.url.contains('#')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      );
    return c;
  }

  static String withBridge(String html) {
    final headIndex = html.toLowerCase().indexOf('<head>');
    if (headIndex >= 0) {
      final at = headIndex + 6;
      return html.substring(0, at) + _consoleBridge + html.substring(at);
    }
    return '<!doctype html><html><head><meta charset="utf-8">$_consoleBridge</head><body>$html</body></html>';
  }

  void _load() {
    if (_controller == null || _loaded == widget.html) return;
    _loaded = widget.html;
    _controller!.loadHtmlString(withBridge(widget.html), baseUrl: widget.baseUrl);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (!ref.watch(webPreviewSupportedProvider)) {
      return Center(
        child: Text('common.preview_unavailable'.tr(), style: TextStyles.body.copyWith(color: c.textSubtle)),
      );
    }
    _controller ??= _create();
    _load();
    return WebViewWidget(controller: _controller!);
  }
}

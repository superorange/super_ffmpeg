import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/workbench.dart';
import '../encode_module.dart';
import '../logic/codecs.dart';

/// Breaks a URL into its parts and query parameters.
class UrlPage extends StatefulWidget {
  const UrlPage({super.key});

  @override
  State<UrlPage> createState() => _UrlPageState();
}

class _UrlPageState extends State<UrlPage> {
  final _input = TextEditingController(
    text: 'https://user:pass@api.example.com:8443/v1/search/items?q=%E8%80%B3%E6%9C%BA&page=2&tag=a&tag=b#results',
  );

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final parts = UrlParts.tryParse(_input.text);
    final u = parts?.uri;
    final rows = u == null
        ? const <(String, String)>[]
        : [
            ('url.scheme'.tr(), u.scheme),
            if (u.userInfo.isNotEmpty) ('url.user'.tr(), Uri.decodeComponent(u.userInfo)),
            ('url.host'.tr(), u.host),
            ('url.port'.tr(), u.hasPort ? '${u.port}' : '${u.port} (${'url.default'.tr()})'),
            ('url.path'.tr(), Uri.decodeFull(u.path)),
            if (u.pathSegments.isNotEmpty) ('url.segments'.tr(), u.pathSegments.join('  ›  ')),
            ('url.query'.tr(), u.query.isEmpty ? '' : Uri.decodeQueryComponent(u.query)),
            ('url.fragment'.tr(), u.fragment),
            ('url.origin'.tr(), u.hasAuthority && (u.scheme == 'http' || u.scheme == 'https') ? u.origin : ''),
          ];

    return ToolScaffold(
      tool: encodeTool('url'),
      toolbar: TextField(
        controller: _input,
        minLines: 1,
        maxLines: 3,
        style: TextStyles.mono.copyWith(fontSize: 13, color: c.text),
        decoration: InputDecoration(
          hintText: 'https://…',
          prefixIcon: Icon(Icons.link_rounded, size: 18, color: c.textSubtle),
          errorText: _input.text.trim().isNotEmpty && parts == null ? 'url.invalid'.tr() : null,
        ),
      ),
      body: SplitPane(
        first: Pane(
          title: 'url.parts'.tr(),
          icon: Icons.account_tree_outlined,
          padding: const EdgeInsets.all(6),
          child: ListView(
            children: [for (final (k, v) in rows) ValueRow(label: k, value: v)],
          ),
        ),
        second: Pane(
          title: 'url.params'.tr(namedArgs: {'n': '${parts?.query.length ?? 0}'}),
          icon: Icons.tune_rounded,
          actions: [
            if (parts != null) CopyAction(text: () => parts.query.map((e) => '${e.$1}=${e.$2}').join('\n')),
          ],
          padding: const EdgeInsets.all(6),
          child: parts == null || parts.query.isEmpty
              ? Center(
                  child: Text('url.no_params'.tr(), style: TextStyles.body.copyWith(color: c.textSubtle)),
                )
              : ListView(
                  children: [
                    for (final (k, v) in parts.query) ValueRow(label: k, value: v),
                  ],
                ),
        ),
      ),
    );
  }
}

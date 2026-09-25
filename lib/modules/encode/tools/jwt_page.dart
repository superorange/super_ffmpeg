import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/code_area.dart';
import '../../../ui/widgets/feedback.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/workbench.dart';
import '../../generate/logic/time_tools.dart';
import '../encode_module.dart';
import '../logic/jwt.dart';

const _sampleToken =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.'
    'SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';

enum _Mode { decode, encode }

class JwtPage extends StatefulWidget {
  const JwtPage({super.key});

  @override
  State<JwtPage> createState() => _JwtPageState();
}

class _JwtPageState extends State<JwtPage> {
  var _mode = _Mode.decode;
  final _token = TextEditingController(text: _sampleToken);
  final _secret = TextEditingController(text: 'your-256-bit-secret');
  final _header = CodeLineEditingController();
  final _payload = CodeLineEditingController();
  var _secretB64 = false;
  DecodedJwt? _jwt;
  String? _error;

  // Encode mode.
  final _newPayload = CodeLineEditingController.fromText(
    const JsonEncoder.withIndent('  ').convert({
      'sub': 'user-42',
      'name': 'Super Toolbox',
      'role': 'admin',
      'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'exp': DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000,
    }),
  );
  var _alg = JwtAlg.hs256;
  String _signed = '';
  String? _signError;

  @override
  void initState() {
    super.initState();
    _token.addListener(outsideBuild(_decode));
    _secret.addListener(
      outsideBuild(() {
        _sign();
        setState(() {});
      }),
    );
    _newPayload.addListener(outsideBuild(_sign));
    _decode();
    _sign();
  }

  @override
  void dispose() {
    _token.dispose();
    _secret.dispose();
    _header.dispose();
    _payload.dispose();
    _newPayload.dispose();
    super.dispose();
  }

  void _decode() {
    try {
      _jwt = _token.text.trim().isEmpty ? null : Jwt.decode(_token.text);
      _error = null;
    } on FormatException catch (e) {
      _jwt = null;
      _error = e.message;
    }
    const enc = JsonEncoder.withIndent('  ');
    _header.text = _jwt == null ? '' : enc.convert(_jwt!.header);
    _payload.text = _jwt == null ? '' : enc.convert(_jwt!.payload);
    if (mounted) setState(() {});
  }

  void _sign() {
    try {
      final payload = jsonDecode(_newPayload.text);
      if (payload is! Map<String, dynamic>) throw const FormatException('Payload must be a JSON object');
      _signed = Jwt.sign(payload, _secret.text, alg: _alg);
      _signError = null;
    } on FormatException catch (e) {
      _signed = '';
      _signError = e.message;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final partColors = [const Color(0xFFFB7185), const Color(0xFFA78BFA), const Color(0xFF22D3EE)];

    final secretField = Row(
      children: [
        Expanded(
          child: TextField(
            controller: _secret,
            style: TextStyles.mono.copyWith(fontSize: 12.5, color: c.text),
            decoration: InputDecoration(
              labelText: 'jwt.secret'.tr(),
              prefixIcon: Icon(Icons.password_rounded, size: 16, color: c.textSubtle),
            ),
          ),
        ),
        if (_mode == _Mode.decode) ...[
          const SizedBox(width: 10),
          Text('jwt.secret_b64'.tr(), style: TextStyles.label.copyWith(color: c.textSubtle)),
          const SizedBox(width: 6),
          AppSwitch(value: _secretB64, onChanged: (v) => setState(() => _secretB64 = v)),
        ],
      ],
    );

    Widget decode() {
      final jwt = _jwt;
      final sig = jwt?.verify(_secret.text, secretIsBase64: _secretB64);
      final parts = _token.text.trim().split('.');
      final tokenPane = Pane(
        title: 'jwt.token'.tr(),
        icon: Icons.key_rounded,
        actions: [
          PaneAction(
            icon: Icons.content_paste_rounded,
            tooltip: 'common.paste'.tr(),
            onPressed: () async => _token.text = await readClipboard() ?? _token.text,
          ),
          PaneAction(icon: Icons.backspace_outlined, tooltip: 'common.clear'.tr(), onPressed: _token.clear),
        ],
        footer: _error != null ? StatusLine(_error!, tone: StatusTone.danger) : StatusLine('jwt.structure'.tr()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: TextArea(controller: _token)),
            if (parts.length == 3)
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.control)),
                child: SingleChildScrollView(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        for (var i = 0; i < 3; i++) ...[
                          if (i > 0)
                            TextSpan(
                              text: '.',
                              style: TextStyle(color: c.textSubtle),
                            ),
                          TextSpan(
                            text: parts[i],
                            style: TextStyle(color: partColors[i]),
                          ),
                        ],
                      ],
                    ),
                    style: TextStyles.mono.copyWith(fontSize: 11.5),
                  ),
                ),
              ),
          ],
        ),
      );

      final claims = jwt == null
          ? const <Widget>[]
          : [
              if (jwt.expiresAt != null)
                _Claim(
                  label: 'exp',
                  time: jwt.expiresAt!,
                  tag: jwt.isExpired()
                      ? Tag('jwt.expired'.tr(), color: c.danger)
                      : Tag('jwt.valid_until'.tr(), color: c.success),
                ),
              if (jwt.issuedAt != null) _Claim(label: 'iat', time: jwt.issuedAt!),
              if (jwt.notBefore != null)
                _Claim(
                  label: 'nbf',
                  time: jwt.notBefore!,
                  tag: jwt.isNotYetValid() ? Tag('jwt.not_yet'.tr(), color: c.warning) : null,
                ),
            ];

      final (sigColor, sigText) = switch (sig) {
        JwtSignature.valid => (c.success, 'jwt.sig_valid'.tr()),
        JwtSignature.invalid => (c.danger, 'jwt.sig_invalid'.tr()),
        JwtSignature.unsupported => (c.warning, 'jwt.sig_unsupported'.tr(namedArgs: {'alg': jwt?.alg ?? '?'})),
        _ => (c.textSubtle, 'jwt.sig_unchecked'.tr()),
      };

      final decoded = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 130,
            child: Pane(
              title: 'jwt.header'.tr(),
              color: c.codeBg,
              actions: [CopyAction(text: () => _header.text)],
              child: CodeArea(controller: _header, language: CodeLang.json, readOnly: true, lineNumbers: false),
            ),
          ),
          const SizedBox(height: Space.md),
          Expanded(
            child: Pane(
              title: 'jwt.payload'.tr(),
              color: c.codeBg,
              actions: [CopyAction(text: () => _payload.text)],
              footer: claims.isEmpty ? null : Column(children: claims),
              child: CodeArea(controller: _payload, language: CodeLang.json, readOnly: true, lineNumbers: false),
            ),
          ),
          const SizedBox(height: Space.md),
          Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(Radii.card),
              border: Border.all(color: sig == JwtSignature.valid ? c.success.withValues(alpha: 0.5) : c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                secretField,
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      sig == JwtSignature.valid ? Icons.verified_rounded : Icons.shield_outlined,
                      size: 16,
                      color: sigColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        sigText,
                        style: TextStyles.label.copyWith(color: sigColor, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
      return SplitPane(initial: 0.42, first: tokenPane, second: decoded);
    }

    Widget encode() => SplitPane(
      first: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Pane(
              title: 'jwt.payload'.tr(),
              color: c.codeBg,
              footer: _signError == null ? null : StatusLine(_signError!, tone: StatusTone.danger),
              child: CodeArea(controller: _newPayload, language: CodeLang.json),
            ),
          ),
          const SizedBox(height: Space.md),
          Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(Radii.card),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Segmented<JwtAlg>(
                  value: _alg,
                  onChanged: (v) {
                    setState(() => _alg = v);
                    _sign();
                  },
                  items: [for (final a in JwtAlg.values) ChoiceItem(a, a.name)],
                ),
                const SizedBox(height: 10),
                secretField,
              ],
            ),
          ),
        ],
      ),
      second: Pane(
        title: 'jwt.token'.tr(),
        icon: Icons.key_rounded,
        actions: [
          CopyAction(text: () => _signed),
          PaneAction(
            icon: Icons.open_in_new_rounded,
            tooltip: 'jwt.open_decoder'.tr(),
            onPressed: _signed.isEmpty
                ? null
                : () {
                    _token.text = _signed;
                    setState(() => _mode = _Mode.decode);
                  },
          ),
        ],
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: SelectableText.rich(
            TextSpan(
              children: [
                for (final (i, part) in _signed.split('.').indexed) ...[
                  if (i > 0)
                    TextSpan(
                      text: '.',
                      style: TextStyle(color: c.textSubtle),
                    ),
                  TextSpan(
                    text: part,
                    style: TextStyle(color: partColors[i % 3]),
                  ),
                ],
              ],
            ),
            style: TextStyles.mono.copyWith(fontSize: 13),
          ),
        ),
      ),
    );

    return ToolScaffold(
      tool: encodeTool('jwt'),
      toolbar: ToolbarRow(
        children: [
          Segmented<_Mode>(
            expand: false,
            value: _mode,
            onChanged: (v) => setState(() => _mode = v),
            items: [
              ChoiceItem(_Mode.decode, 'jwt.decode'.tr(), icon: Icons.lock_open_rounded),
              ChoiceItem(_Mode.encode, 'jwt.encode'.tr(), icon: Icons.edit_outlined),
            ],
          ),
        ],
      ),
      body: _mode == _Mode.decode ? decode() : encode(),
    );
  }
}

class _Claim extends StatelessWidget {
  const _Claim({required this.label, required this.time, this.tag});
  final String label;
  final DateTime time;
  final Widget? tag;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (n, unit, future) = TimeTools.relative(time);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(label, style: TextStyles.mono.copyWith(fontSize: 12, color: c.accent)),
          ),
          Text(TimeTools.dateTime(time.toLocal()), style: TextStyles.mono.copyWith(fontSize: 12, color: c.text)),
          const SizedBox(width: 8),
          Text(
            'time.${future ? 'in' : 'ago'}'.tr(namedArgs: {'n': '$n', 'unit': 'time.units.$unit'.tr()}),
            style: TextStyles.caption.copyWith(color: c.textSubtle),
          ),
          const Spacer(),
          ?tag,
        ],
      ),
    );
  }
}

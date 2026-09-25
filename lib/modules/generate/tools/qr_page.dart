import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/buttons.dart';
import '../../../ui/widgets/feedback.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/layout.dart';
import '../../../ui/widgets/workbench.dart';
import '../generate_module.dart';

enum _Kind { text, wifi }

class QrPage extends StatefulWidget {
  const QrPage({super.key});

  @override
  State<QrPage> createState() => _QrPageState();
}

class _QrPageState extends State<QrPage> {
  var _kind = _Kind.text;
  final _text = TextEditingController(text: 'https://github.com');
  final _ssid = TextEditingController(text: 'MyWiFi');
  final _wifiPass = TextEditingController(text: 'password123');
  var _ecc = QrErrorCorrectLevel.medium;
  var _fg = const Color(0xFF111118);
  var _bg = Colors.white;

  static const _palette = [
    Color(0xFF111118),
    Color(0xFF6554F0),
    Color(0xFFE11D48),
    Color(0xFF0E9F6E),
    Color(0xFF2563EB),
    Color(0xFFD97706),
  ];

  @override
  void initState() {
    super.initState();
    for (final t in [_text, _ssid, _wifiPass]) {
      t.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _ssid.dispose();
    _wifiPass.dispose();
    super.dispose();
  }

  String get _data {
    if (_kind == _Kind.text) return _text.text;
    String esc(String s) => s.replaceAllMapped(RegExp(r'([\;,:"])'), (m) => '\\${m[1]}');
    return 'WIFI:T:${_wifiPass.text.isEmpty ? 'nopass' : 'WPA'};S:${esc(_ssid.text)};P:${esc(_wifiPass.text)};;';
  }

  QrImage? _image(String data) {
    if (data.isEmpty) return null;
    try {
      return QrImage(QrCode(payload: QrPayload.fromString(data), errorCorrectLevel: _ecc));
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(QrImage img) async {
    final path = await FilePicker.platform.saveFile(fileName: 'qrcode.png');
    if (path == null) return;
    const size = 1024.0;
    final recorder = ui.PictureRecorder();
    _QrPainter(img, _fg, _bg).paint(Canvas(recorder), const Size(size, size));
    final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await File(path).writeAsBytes(png!.buffer.asUint8List());
    if (mounted) showToast(context, 'common.saved'.tr(namedArgs: {'path': path}));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final data = _data;
    final img = _image(data);

    Widget swatches(Color value, ValueChanged<Color> onPick, List<Color> colors) => Wrap(
      spacing: 6,
      children: [
        for (final col in colors)
          GestureDetector(
            onTap: () => onPick(col),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: col,
                  shape: BoxShape.circle,
                  border: Border.all(color: value == col ? c.accent : c.border, width: value == col ? 2.5 : 1),
                ),
              ),
            ),
          ),
      ],
    );

    final form = Panel(
      title: 'qrcode.content'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Segmented<_Kind>(
            value: _kind,
            onChanged: (v) => setState(() => _kind = v),
            items: [
              ChoiceItem(_Kind.text, 'qrcode.text'.tr(), icon: Icons.link_rounded),
              ChoiceItem(_Kind.wifi, 'Wi-Fi', icon: Icons.wifi_rounded),
            ],
          ),
          const SizedBox(height: Space.lg),
          if (_kind == _Kind.text)
            TextField(
              controller: _text,
              minLines: 4,
              maxLines: 10,
              style: TextStyles.body.copyWith(color: c.text),
              decoration: InputDecoration(hintText: 'qrcode.text_hint'.tr()),
            )
          else ...[
            TextField(
              controller: _ssid,
              decoration: InputDecoration(labelText: 'qrcode.ssid'.tr()),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _wifiPass,
              decoration: InputDecoration(labelText: 'qrcode.wifi_password'.tr()),
            ),
          ],
          const SizedBox(height: Space.xl),
          OptionField(
            label: 'qrcode.ecc'.tr(),
            hint: 'qrcode.ecc_hint'.tr(),
            child: Segmented<QrErrorCorrectLevel>(
              value: _ecc,
              onChanged: (v) => setState(() => _ecc = v),
              items: const [
                ChoiceItem(QrErrorCorrectLevel.low, 'L 7%'),
                ChoiceItem(QrErrorCorrectLevel.medium, 'M 15%'),
                ChoiceItem(QrErrorCorrectLevel.quartile, 'Q 25%'),
                ChoiceItem(QrErrorCorrectLevel.high, 'H 30%'),
              ],
            ),
          ),
          OptionField(
            label: 'qrcode.foreground'.tr(),
            child: swatches(_fg, (v) => setState(() => _fg = v), _palette),
          ),
          OptionField(
            label: 'qrcode.background'.tr(),
            child: swatches(_bg, (v) => setState(() => _bg = v), const [
              Colors.white,
              Color(0xFFF5F3FF),
              Color(0xFFFFF7ED),
              Color(0xFFECFDF5),
              Color(0x00FFFFFF),
            ]),
          ),
        ],
      ),
    );

    final preview = Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.panel),
        border: Border.all(color: c.border),
        boxShadow: c.cardShadow,
      ),
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: img == null
                  ? Text(
                      data.isEmpty ? 'qrcode.empty'.tr() : 'qrcode.too_long'.tr(),
                      style: TextStyles.body.copyWith(color: c.textSubtle),
                    )
                  : AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Radii.card),
                          boxShadow: [BoxShadow(color: c.shadow, blurRadius: 30, offset: const Offset(0, 10))],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.card),
                          child: CustomPaint(painter: _QrPainter(img, _fg, _bg)),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: Space.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (img != null)
                Text(
                  '${img.moduleCount}×${img.moduleCount} · ${data.length} ${'common.chars_unit'.tr()}',
                  style: TextStyles.caption.copyWith(color: c.textSubtle),
                ),
              const SizedBox(width: Space.lg),
              AppButton.primary(
                label: 'qrcode.save_png'.tr(),
                icon: Icons.download_rounded,
                onPressed: img == null ? null : () => _save(img),
              ),
            ],
          ),
        ],
      ),
    );

    return ToolScaffold(
      tool: generateTool('qrcode'),
      body: SplitPane(
        initial: 0.45,
        first: SingleChildScrollView(child: form),
        second: preview,
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image, this.fg, this.bg);
  final QrImage image;
  final Color fg;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    final n = image.moduleCount;
    const quiet = 2; // modules of margin
    final cell = size.width / (n + quiet * 2);
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    final paint = Paint()
      ..color = fg
      ..isAntiAlias = false;
    for (var r = 0; r < n; r++) {
      for (var col = 0; col < n; col++) {
        if (image.isDark(r, col)) {
          canvas.drawRect(
            Rect.fromLTWH((col + quiet) * cell, (r + quiet) * cell, cell + 0.5, cell + 0.5),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image || old.fg != fg || old.bg != bg;
}

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings.dart';
import '../../core/utils/platform_actions.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/buttons.dart';
import '../../ui/widgets/feedback.dart';
import '../../ui/widgets/inputs.dart';
import '../../ui/widgets/layout.dart';
import '../media/providers.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);

    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Panel(
        title: title,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );

    return Scaffold(
      backgroundColor: c.bg,
      body: ListView(
        children: [
          PageHeader(title: 'settings.title'.tr(), subtitle: 'settings.subtitle'.tr()),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.xxxl, 0, Space.xxxl, Space.xxxl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    section('settings.appearance'.tr(), [
                      OptionField(
                        label: 'settings.theme'.tr(),
                        child: Segmented<ThemeMode>(
                          value: s.themeMode,
                          onChanged: n.setThemeMode,
                          items: [
                            ChoiceItem(
                              ThemeMode.system,
                              'settings.theme_system'.tr(),
                              icon: Icons.brightness_auto_rounded,
                            ),
                            ChoiceItem(ThemeMode.light, 'settings.theme_light'.tr(), icon: Icons.light_mode_rounded),
                            ChoiceItem(ThemeMode.dark, 'settings.theme_dark'.tr(), icon: Icons.dark_mode_rounded),
                          ],
                        ),
                      ),
                      OptionField(
                        label: 'settings.language'.tr(),
                        child: Segmented<String>(
                          value: context.locale.languageCode,
                          onChanged: (v) =>
                              context.setLocale(v == 'zh' ? const Locale('zh', 'CN') : const Locale('en')),
                          items: const [ChoiceItem('zh', '简体中文'), ChoiceItem('en', 'English')],
                        ),
                      ),
                    ]),
                    section('settings.engine'.tr(), [const _EngineSection()]),
                    section('settings.output'.tr(), [
                      OptionField(
                        label: 'settings.output_location'.tr(),
                        child: Segmented<bool>(
                          value: s.outputDir != null,
                          onChanged: (custom) async {
                            if (!custom) return n.setOutputDir(null);
                            final dir = await FilePicker.platform.getDirectoryPath();
                            if (dir != null) n.setOutputDir(dir);
                          },
                          items: [
                            ChoiceItem(false, 'media.output_next_to_source'.tr()),
                            ChoiceItem(true, 'settings.output_custom'.tr()),
                          ],
                        ),
                      ),
                      if (s.outputDir != null)
                        _PathRow(
                          path: s.outputDir!,
                          onChange: () async {
                            final dir = await FilePicker.platform.getDirectoryPath();
                            if (dir != null) n.setOutputDir(dir);
                          },
                        ),
                      Text('settings.output_hint'.tr(), style: TextStyles.caption.copyWith(color: c.textSubtle)),
                    ]),
                    section('settings.performance'.tr(), [
                      OptionField(
                        label: 'settings.concurrency'.tr(),
                        hint: 'settings.concurrency_hint'.tr(),
                        child: Segmented<int>(
                          value: s.concurrency,
                          onChanged: n.setConcurrency,
                          items: [
                            for (final i in const [1, 2, 3, 4]) ChoiceItem(i, '$i'),
                          ],
                        ),
                      ),
                      OptionRow(
                        label: 'media.gpu.label'.tr(),
                        hint: 'media.gpu.hint'.tr(),
                        control: AppSwitch(value: s.preferGpu, onChanged: n.setPreferGpu),
                      ),
                    ]),
                    section('settings.about'.tr(), [
                      KeyValueList(
                        entries: [
                          ('settings.version'.tr(), '0.2.0'),
                          ('settings.privacy'.tr(), 'settings.privacy_value'.tr()),
                        ],
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EngineSection extends ConsumerWidget {
  const _EngineSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final bin = ref.watch(ffmpegBinariesProvider);
    final caps = ref.watch(ffmpegCapabilitiesProvider);
    final customDir = ref.watch(settingsProvider.select((s) => s.ffmpegDir));
    final nativeOn = ref.watch(nativeMediaAvailableProvider);
    final n = ref.read(settingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (bin == null)
          Notice(tone: NoticeTone.danger, message: 'media.engine_missing.message'.tr())
        else
          KeyValueList(
            entries: [
              (
                'settings.engine_version'.tr(),
                switch (caps) {
                  AsyncData(:final value) => value.version,
                  AsyncError(:final error) => '$error',
                  _ => '…',
                },
              ),
              ('settings.engine_source'.tr(), 'settings.source_${bin.source.name}'.tr()),
              ('settings.native_decode'.tr(), (nativeOn ? 'settings.native_on' : 'settings.native_off').tr()),
              ('ffmpeg', bin.ffmpeg),
              if (caps.value case final v?) ('settings.encoders'.tr(), '${v.encoders.length}'),
            ],
          ),
        if (caps.value case final v? when v.gpuEncoders.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          Text('settings.gpu_encoders'.tr(), style: TextStyles.label.copyWith(color: c.text)),
          const SizedBox(height: Space.sm),
          Wrap(spacing: 5, runSpacing: 5, children: [for (final e in v.gpuEncoders) Tag(e, color: c.success)]),
        ],
        const SizedBox(height: Space.lg),
        OptionRow(
          label: 'settings.engine_dir'.tr(),
          hint: customDir ?? 'settings.engine_auto'.tr(),
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (customDir != null)
                AppButton.ghost(
                  label: 'settings.reset'.tr(),
                  size: ButtonSize.sm,
                  onPressed: () => n.setFfmpegDir(null),
                ),
              const SizedBox(width: 4),
              AppButton(
                label: 'settings.choose'.tr(),
                size: ButtonSize.sm,
                onPressed: () async {
                  final dir = await FilePicker.platform.getDirectoryPath();
                  if (dir != null) n.setFfmpegDir(dir);
                },
              ),
              const SizedBox(width: 4),
              AppIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'settings.redetect'.tr(),
                onPressed: () => ref.invalidate(ffmpegBinariesProvider),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PathRow extends StatelessWidget {
  const _PathRow({required this.path, required this.onChange});
  final String path;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Container(
        padding: const EdgeInsets.fromLTRB(Space.md, 6, 6, 6),
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Icon(Icons.folder_rounded, size: 16, color: c.textSubtle),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                path,
                overflow: TextOverflow.ellipsis,
                style: TextStyles.body.copyWith(color: c.text),
              ),
            ),
            AppIconButton(
              icon: Icons.open_in_new_rounded,
              tooltip: 'common.open_folder'.tr(),
              onPressed: () => PlatformActions.open(path),
            ),
            AppButton.ghost(label: 'settings.choose'.tr(), size: ButtonSize.sm, onPressed: onChange),
          ],
        ),
      ),
    );
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/buttons.dart';
import '../../../ui/widgets/feedback.dart';
import '../../../ui/widgets/layout.dart';
import '../providers.dart';

/// Shown in place of a media tool when ffmpeg can't be found.
class EngineMissingView extends ConsumerWidget {
  const EngineMissingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    const install = 'brew install ffmpeg';
    return Scaffold(
      backgroundColor: c.bg,
      body: EmptyState(
        icon: Icons.extension_off_rounded,
        title: 'media.engine_missing.title'.tr(),
        message: 'media.engine_missing.message'.tr(),
        action: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(Radii.control),
                border: Border.all(color: c.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(install, style: TextStyles.mono.copyWith(color: c.text)),
                  const SizedBox(width: Space.sm),
                  AppIconButton(
                    icon: Icons.copy_rounded,
                    tooltip: 'common.copy'.tr(),
                    onPressed: () {
                      Clipboard.setData(const ClipboardData(text: install));
                      showToast(context, 'common.copied'.tr());
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.lg),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppButton(
                  label: 'media.engine_missing.retry'.tr(),
                  icon: Icons.refresh_rounded,
                  onPressed: () => ref.invalidate(ffmpegBinariesProvider),
                ),
                const SizedBox(width: Space.sm),
                AppButton.primary(
                  label: 'media.engine_missing.settings'.tr(),
                  onPressed: () => context.go('/settings'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

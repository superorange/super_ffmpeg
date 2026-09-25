import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../core/jobs/job_queue.dart';
import '../../../core/settings/settings.dart';
import '../../../core/toolbox/file_intake.dart';
import '../../../core/utils/format.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/buttons.dart';
import '../../../ui/widgets/feedback.dart';
import '../../../ui/widgets/inputs.dart';
import '../../../ui/widgets/layout.dart';
import '../../../ui/widgets/workbench.dart';
import '../../media/engine/media_job.dart';
import '../../media/providers.dart';
import '../../media/studio/tool_panel.dart';
import '../../media/widgets/engine_missing.dart';
import '../../media/widgets/media_file_tile.dart';
import '../../media/widgets/output_planner.dart';
import '../image_module.dart';
import '../logic/image_convert.dart';

/// Batch convert / compress / resize images; metadata is always stripped.
class ImageConvertPage extends ConsumerStatefulWidget {
  const ImageConvertPage({super.key});

  @override
  ConsumerState<ImageConvertPage> createState() => _ImageConvertPageState();
}

class _ImageConvertPageState extends ConsumerState<ImageConvertPage> with FileIntakeMixin {
  final _files = <String>[];
  var _o = const ImageOptions();
  var _showCommand = false;

  @override
  String get intakeId => 'image_convert';

  @override
  void onFiles(List<String> paths) {
    final images = paths.where((f) => imageExtensions.contains(p.extension(f).replaceFirst('.', '').toLowerCase()));
    final fresh = images.where((f) => !_files.contains(f)).toList();
    final ignored = paths.length - images.length;
    setState(() => _files.addAll(fresh));
    if (ignored > 0) showToast(context, 'media.ignored_files'.tr(namedArgs: {'n': '$ignored'}));
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: imageExtensions.toList(),
    );
    if (r != null) onFiles([for (final f in r.files) ?f.path]);
  }

  List<PlannedJob> _plan(AppSettings settings) {
    final out = OutputPlanner(outputDir: settings.outputDir);
    return [
      for (final f in _files)
        if (ref.read(probeProvider(f)).value case final info?)
          () {
            final ext = p.extension(f).replaceFirst('.', '').toLowerCase();
            final format = effectiveFormat(_o.format, ext);
            final same = format.extension == (ext == 'jpeg' ? 'jpg' : (ext == 'tif' ? 'tiff' : ext));
            return PlannedJob(
              inputs: [f],
              plan: buildImageConvert(
                input: f,
                output: out.file(f, extension: format.extension, suffix: same ? 'min' : ''),
                format: format,
                options: _o,
                info: info,
              ),
            );
          }(),
    ];
  }

  void _start(List<PlannedJob> jobs, String ffmpeg) {
    final name = 'tools.image_convert.name'.tr();
    ref.read(jobQueueProvider.notifier).enqueueAll([
      for (final j in jobs)
        MediaJobSpec(
          title: '$name · ${p.basename(j.inputs.first)}',
          toolId: 'image_convert',
          inputs: j.inputs,
          plan: j.plan,
          ffmpeg: ffmpeg,
        ),
    ]);
    ref.read(settingsProvider.notifier).markToolUsed('image_convert');
    showToast(
      context,
      'media.queued'.tr(namedArgs: {'n': '${jobs.length}'}),
      actionLabel: 'media.view_tasks'.tr(),
      onAction: () => context.go('/tasks'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final capsAsync = ref.watch(ffmpegCapabilitiesProvider);
    if (capsAsync.error is EngineMissingException) return const EngineMissingView();
    final settings = ref.watch(settingsProvider);
    // Watch probes so the plan refreshes as files are read.
    final pending = _files.any((f) => ref.watch(probeProvider(f)).isLoading);
    final jobs = pending ? const <PlannedJob>[] : _plan(settings);
    final lossy = effectiveFormat(_o.format, 'jpg').lossy || _o.format == PictureFormat.original;

    final files = _files.isEmpty
        ? _DropArea(onTap: _pick)
        : LayoutBuilder(
            builder: (context, box) {
              final cols = (box.maxWidth / 190).floor().clamp(1, 8);
              return GridView.builder(
                padding: const EdgeInsets.only(bottom: Space.lg),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: Space.md,
                  crossAxisSpacing: Space.md,
                  childAspectRatio: 0.95,
                ),
                itemCount: _files.length,
                itemBuilder: (_, i) => _ImageCard(
                  path: _files[i],
                  onRemove: () => setState(() => _files.removeAt(i)),
                ),
              );
            },
          );

    final options = Panel(
      title: 'media.options'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OptionField(
            label: 'image.format'.tr(),
            child: ChoiceChips<PictureFormat>(
              value: _o.format,
              onChanged: (v) => setState(() => _o = _o.copyWith(format: v)),
              items: [
                const ChoiceItem(PictureFormat.jpg, 'JPG'),
                ChoiceItem(PictureFormat.avif, 'AVIF', hint: 'image.avif_hint'.tr()),
                ChoiceItem(PictureFormat.png, 'PNG', hint: 'image.lossless'.tr()),
                const ChoiceItem(PictureFormat.tiff, 'TIFF'),
                const ChoiceItem(PictureFormat.bmp, 'BMP'),
                ChoiceItem(PictureFormat.original, 'image.keep_format'.tr()),
              ],
            ),
          ),
          if (lossy)
            OptionField(
              label: 'image.quality'.tr(),
              hint: 'image.quality_hint'.tr(),
              child: LabeledSlider(
                value: _o.quality.toDouble(),
                min: 10,
                max: 100,
                divisions: 18,
                format: (v) => '${v.round()}',
                onChanged: (v) => setState(() => _o = _o.copyWith(quality: v.round())),
              ),
            ),
          OptionField(
            label: 'image.max_side'.tr(),
            hint: 'image.max_side_hint'.tr(),
            child: ChoiceChips<int?>(
              value: _o.maxSide,
              onChanged: (v) => setState(() => _o = _o.copyWith(maxSide: () => v)),
              items: [
                ChoiceItem(null, 'media.original'.tr()),
                for (final s in const [3840, 2560, 1920, 1280, 800]) ChoiceItem(s, '$s'),
              ],
            ),
          ),
          Notice(tone: NoticeTone.success, message: 'image.privacy'.tr()),
        ],
      ),
    );

    return ToolScaffold(
      tool: imageTool('image_convert'),
      onFiles: onFiles,
      padding: EdgeInsets.zero,
      actions: [
        if (_files.isNotEmpty) ...[
          AppButton(label: 'media.add_files'.tr(), icon: Icons.add_rounded, size: ButtonSize.sm, onPressed: _pick),
          AppButton.ghost(label: 'common.clear'.tr(), size: ButtonSize.sm, onPressed: () => setState(_files.clear)),
        ],
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: files),
                  const SizedBox(width: Space.lg),
                  SizedBox(width: 340, child: SingleChildScrollView(child: options)),
                ],
              ),
            ),
          ),
          RunBar(
            actionLabel: 'image.action'.tr(namedArgs: {'n': '${jobs.length}'}),
            error: null,
            pending: pending,
            jobs: jobs,
            showCommand: _showCommand,
            onToggleCommand: () => setState(() => _showCommand = !_showCommand),
            onStart: jobs.isEmpty || capsAsync.value == null
                ? null
                : () => _start(_plan(settings), capsAsync.value!.binaries.ffmpeg),
          ),
        ],
      ),
    );
  }
}

class _DropArea extends StatefulWidget {
  const _DropArea({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_DropArea> createState() => _DropAreaState();
}

class _DropAreaState extends State<_DropArea> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.normal,
          height: 360,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFF97316).withValues(alpha: _hover ? 0.16 : 0.08),
                c.accent.withValues(alpha: _hover ? 0.14 : 0.05),
              ],
            ),
            border: Border.all(color: _hover ? c.accent : c.borderStrong),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [Color(0xFFF97316), Color(0xFFFBBF24)]),
                ),
                child: const Icon(Icons.add_photo_alternate_rounded, color: Colors.white, size: 30),
              ),
              const SizedBox(height: Space.lg),
              Text('image.drop'.tr(), style: TextStyles.title.copyWith(color: c.text)),
              const SizedBox(height: 6),
              Text('image.drop_hint'.tr(), style: TextStyles.body.copyWith(color: c.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageCard extends ConsumerWidget {
  const _ImageCard({required this.path, required this.onRemove});
  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final info = ref.watch(probeProvider(path));
    final v = info.value?.video;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: info.hasError ? c.danger.withValues(alpha: 0.5) : c.border),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (_, box) => MediaThumbnail(
                      path: path,
                      width: box.maxWidth,
                      height: box.maxHeight,
                      fit: BoxFit.cover,
                      background: c.surfaceAlt,
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                    child: AppIconButton(
                      icon: Icons.close_rounded,
                      tooltip: 'common.remove'.tr(),
                      size: 24,
                      color: Colors.white,
                      onPressed: onRemove,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            p.basename(path),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyles.label.copyWith(color: c.text, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            info.hasError
                ? 'media.unreadable'.tr()
                : [
                    if (v != null && !(info.value?.isTiledImage ?? false)) '${v.displayWidth}×${v.displayHeight}',
                    p.extension(path).replaceFirst('.', '').toUpperCase(),
                    if ((info.value?.sizeBytes ?? 0) > 0) Fmt.bytes(info.value!.sizeBytes),
                  ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyles.caption.copyWith(color: info.hasError ? c.danger : c.textSubtle),
          ),
        ],
      ),
    );
  }
}

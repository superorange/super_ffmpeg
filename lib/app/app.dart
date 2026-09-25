import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/settings/settings.dart';
import '../modules/home/home_page.dart';
import '../modules/media/studio/studio_state.dart';
import '../ui/theme/app_theme.dart';
import 'router.dart';

class SuperToolboxApp extends ConsumerStatefulWidget {
  const SuperToolboxApp({super.key, this.initialLocation = '/', this.initialFiles = const []});
  final String initialLocation;

  /// Files passed on the command line, opened in the fitting tool.
  final List<String> initialFiles;

  @override
  ConsumerState<SuperToolboxApp> createState() => _SuperToolboxAppState();
}

class _SuperToolboxAppState extends ConsumerState<SuperToolboxApp> {
  late final GoRouter _router = buildRouter(initialLocation: widget.initialLocation);

  @override
  void initState() {
    super.initState();
    if (widget.initialFiles.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => openPaths(_router, ref.read(studioProvider.notifier), widget.initialFiles),
      );
    }
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp.router(
      title: 'Super Toolbox',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: _router,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
    );
  }
}

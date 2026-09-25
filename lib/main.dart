import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/settings/settings.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('zh', 'CN'),
      child: ProviderScope(
        // Failed probes (e.g. a non-media file) should stay failed, not retry.
        retry: (_, _) => null,
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: SuperToolboxApp(
          // Dev convenience: SUPER_TOOLBOX_ROUTE=/tool/json opens a page directly.
          initialLocation: Platform.environment['SUPER_TOOLBOX_ROUTE'] ?? '/',
          initialFiles: [
            for (final a in args)
              if (!a.startsWith('-') && File(a).existsSync()) File(a).absolute.path,
          ],
        ),
      ),
    ),
  );
}

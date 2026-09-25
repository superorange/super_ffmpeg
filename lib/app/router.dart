import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../modules/home/home_page.dart';
import '../modules/media/studio/studio_page.dart';
import '../modules/settings/settings_page.dart';
import '../modules/tasks/tasks_page.dart';
import '../ui/theme/tokens.dart';
import 'shell/command_palette.dart';
import 'shell/sidebar.dart';
import 'tool_registry.dart';

GoRouter buildRouter({String initialLocation = '/'}) {
  StatefulShellBranch branch(String path, WidgetBuilder builder) => StatefulShellBranch(
    routes: [
      GoRoute(
        path: path,
        pageBuilder: (context, _) => NoTransitionPage(child: builder(context)),
      ),
    ],
  );

  return GoRouter(
    initialLocation: initialLocation,
    redirect: (context, state) => state.uri.path == '/media' ? '/media/convert' : null,
    routes: [
      // Each page is its own branch so tool state (selected files, options)
      // survives switching between tools.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(location: state.uri.path, child: shell),
        branches: [
          branch('/', (_) => const HomePage()),
          branch('/tasks', (_) => const TasksPage()),
          branch('/settings', (_) => const SettingsPage()),
          // One workspace for every media tool; the tab is part of the URL.
          StatefulShellBranch(
            initialLocation: '/media/convert',
            routes: [
              GoRoute(
                path: '/media/:tab',
                pageBuilder: (context, state) => NoTransitionPage(
                  key: const ValueKey('media-studio'),
                  child: MediaStudioPage(tab: state.pathParameters['tab']!),
                ),
              ),
            ],
          ),
          for (final tool in toolRegistry)
            if (tool.isAvailable && tool.path == null) branch(tool.route, tool.builder!),
        ],
      ),
    ],
  );
}

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => CommandPalette.show(context),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => CommandPalette.show(context),
        const SingleActivator(LogicalKeyboardKey.comma, meta: true): () => context.go('/settings'),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: context.colors.bg,
          child: LayoutBuilder(
            builder: (context, box) => Row(
              children: [
                Sidebar(location: location, compact: box.maxWidth < 900),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

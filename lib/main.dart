import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'state/prefs_providers.dart';
import 'storage/credentials_store.dart';
import 'theme/app_theme.dart';
import 'util/error_logging.dart';

void main() {
  runWithErrorLogging(() async {
    WidgetsFlutterBinding.ensureInitialized();
    installErrorLogging();

    // Send first-launch users straight to Settings to enter their Canvas /
    // Synergy credentials. Once anything has been saved we honor the default
    // root route and the dashboard takes over.
    final creds = await CredentialsStore().read();
    final hasAnyCreds = (creds.canvasToken?.isNotEmpty ?? false) ||
        (creds.synergyUsername?.isNotEmpty ?? false);
    final initialLocation = hasAnyCreds ? '/' : '/settings';

    runApp(ProviderScope(
      child: TrackerApp(initialLocation: initialLocation),
    ));
  });
}

class TrackerApp extends ConsumerStatefulWidget {
  const TrackerApp({super.key, required this.initialLocation});

  final String initialLocation;

  @override
  ConsumerState<TrackerApp> createState() => _TrackerAppState();
}

class _TrackerAppState extends ConsumerState<TrackerApp> {
  // Built once: rebuilding the router on every theme change would reset
  // navigation state.
  late final _router = buildRouter(initialLocation: widget.initialLocation);

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Assignment Tracker',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      routerConfig: _router,
    );
  }
}

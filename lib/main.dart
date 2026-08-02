import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'state/data_providers.dart';
import 'state/prefs_providers.dart';
import 'state/rewards_providers.dart';
import 'storage/credentials_store.dart';
import 'theme/app_theme.dart';
import 'util/error_logging.dart';
import 'widgets/reward_celebration.dart';

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

class _TrackerAppState extends ConsumerState<TrackerApp>
    with WidgetsBindingObserver {
  // Built once: rebuilding the router on every theme change would reset
  // navigation state.
  late final _router = buildRouter(initialLocation: widget.initialLocation);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Covers a payload that had already resolved by the time this mounted —
    // the listen in build only sees transitions. Deferred a frame so nothing
    // touches provider state mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkIn());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Re-check on resume so a phone left open overnight still banks the new
  /// day the next time it's picked up, rather than waiting for a cold launch.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkIn();
  }

  /// Idempotent per calendar day — see [RewardsNotifier.recordVisit]. Fires on
  /// whichever comes first, the data landing or a resume, and does nothing on
  /// every call after that until tomorrow.
  void _checkIn() {
    if (!mounted) return;
    ref.read(rewardServiceProvider).recordVisit();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;

    // The check-in needs a student, and the student only exists once the
    // payload assembles — so it hangs off the data landing rather than
    // initState alone.
    ref.listen(dataProvider, (_, next) {
      if (next.hasValue) _checkIn();
    });

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Assignment Tracker',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      routerConfig: _router,
      // Above the Navigator on purpose: the action that earns points usually
      // pops the sheet you were looking at, and a celebration hosted inside
      // that sheet would go with it.
      builder: (context, child) => RewardHost(child: child ?? const SizedBox()),
    );
  }
}

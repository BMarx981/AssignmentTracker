import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'storage/credentials_store.dart';
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

class TrackerApp extends StatelessWidget {
  const TrackerApp({super.key, required this.initialLocation});

  final String initialLocation;

  @override
  Widget build(BuildContext context) {
    final router = buildRouter(initialLocation: initialLocation);
    return MaterialApp.router(
      title: 'Assignment Tracker',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      ),
      routerConfig: router,
    );
  }
}

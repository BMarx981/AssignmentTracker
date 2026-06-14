import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'util/error_logging.dart';

void main() {
  runWithErrorLogging(() {
    WidgetsFlutterBinding.ensureInitialized();
    installErrorLogging();
    runApp(const ProviderScope(child: TrackerApp()));
  });
}

class TrackerApp extends StatelessWidget {
  const TrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Assignment Tracker',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      ),
      routerConfig: appRouter,
    );
  }
}

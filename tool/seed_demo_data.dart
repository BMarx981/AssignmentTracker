// Writes the demo dataset straight into the app's on-disk store, without
// building or launching the app:
//
//   dart run tool/seed_demo_data.dart              # macOS container path
//   dart run tool/seed_demo_data.dart <state_dir>  # any other LocalStore root
//
// Restart the app afterwards; it reads these files on startup. For iOS or
// Android simulators there is no stable path to target — use the in-app
// Settings → Demo data button instead.
//
// This runs under plain `dart run`, which is why demo_data.dart is kept free
// of Flutter imports.

import 'dart:convert';
import 'dart:io';

import 'package:assignment_tracker_app/dev/demo_data.dart';

/// Mirrors LocalStore's layout: `<appSupport>/<bundle id>/state/`
const _macosStateDir =
    'Library/Containers/com.brianmarx.assignmentTrackerApp/Data/Library/'
    'Application Support/com.brianmarx.assignmentTrackerApp/state';

Future<int> main(List<String> args) async {
  final root = args.isNotEmpty ? args.first : _defaultMacosRoot();
  if (root == null) {
    stderr.writeln(
      'Could not determine the macOS store path. Pass one explicitly:\n'
      '  dart run tool/seed_demo_data.dart <state_dir>',
    );
    return 1;
  }

  final dir = Directory(root);
  if (!dir.existsSync()) {
    stderr.writeln(
      'No store at $root\n'
      'Run the app once so it creates its Application Support directory, '
      'or pass a different path.',
    );
    return 1;
  }

  final files = demoFiles(DateTime.now());
  const encoder = JsonEncoder.withIndent('  ');
  for (final entry in files.entries) {
    final file = File('$root/${entry.key}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(encoder.convert(entry.value));
    stdout.writeln('wrote ${entry.key}');
  }
  stdout.writeln('\nSeeded ${files.length} files into $root');
  stdout.writeln('Restart the app to pick them up.');
  return 0;
}

String? _defaultMacosRoot() {
  if (!Platform.isMacOS) return null;
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) return null;
  return '$home/$_macosStateDir';
}

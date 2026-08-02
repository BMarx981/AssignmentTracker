// LocalStore-facing wrapper around `demo_data.dart`. Kept separate so the
// generator itself stays Flutter-free and can run under plain `dart run`
// (see tool/seed_demo_data.dart).

import 'package:assignment_tracker_app/storage/local_store.dart';

import 'demo_data.dart';

/// Writes the full demo dataset into [store], replacing whatever is there.
///
/// Credentials are left alone — wiping them would log the user out of a real
/// account they may still want.
Future<void> seedDemoData(LocalStore store) async {
  final anchor = DateTime.now();
  await store.writeCanvasData(buildCanvasPayload(anchor));
  await store.writeSynergyData(buildSynergyPayload(anchor));
  await store.writeGradeBands({'failing': 60, 'at_risk': 75});
  for (final student in demoStudents) {
    await store.writeScoreThresholds(student.id, student.thresholds);
    await store.writeComments(student.id, student.comments(anchor));
    await store.writeAssignmentStatus(student.id, {
      'entries': student.statusEntries(anchor),
    });
  }
}

/// Deletes seeded data (and everything else in the store) but preserves
/// credentials so a real fetch still works afterwards.
Future<void> clearDemoData(LocalStore store) async {
  final creds = await store.readCredentials();
  await store.wipe();
  if (creds != null) await store.writeCredentials(creds);
}

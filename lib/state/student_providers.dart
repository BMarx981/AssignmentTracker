// selectedStudentIdProvider is purely local — the FastAPI server-side session
// is gone, so selecting a student just changes which Student in the latest
// DataPayload the UI considers "active".

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:assignment_tracker_app/models/api_models.dart';
import 'data_providers.dart';

class SelectedStudentIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String id) {
    if (state == id) return;
    state = id;
  }
}

final selectedStudentIdProvider =
    NotifierProvider<SelectedStudentIdNotifier, String?>(
        SelectedStudentIdNotifier.new);

/// The currently selected Student inside the latest DataPayload. Falls back to
/// the first student in the payload if no explicit selection has been made.
///
/// autoDispose on purpose: a plain Provider outlives its listeners, so when the
/// screens watching it unmount it lingers alive-but-inactive. The scheduler
/// skips inactive elements on refresh, so an upstream change leaves it stale
/// until the next widget mounts and flushes it *during build* — which throws
/// "setState() called during build" from the ProviderScope. Disposing instead
/// means the next mount always builds it fresh.
final selectedStudentProvider = Provider.autoDispose<AsyncValue<Student?>>((ref) {
  final data = ref.watch(dataProvider);
  final selectedId = ref.watch(selectedStudentIdProvider);
  return data.whenData((p) {
    if (p.students.isEmpty) return null;
    if (selectedId == null) return p.students.first;
    return p.students.firstWhere(
      (s) => s.studentId == selectedId,
      orElse: () => p.students.first,
    );
  });
});

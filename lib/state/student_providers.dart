// selectedStudentIdProvider is purely local — the FastAPI server-side session
// is gone, so selecting a student just changes which Student in the latest
// DataPayload the UI considers "active".

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_models.dart';
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
final selectedStudentProvider = Provider<AsyncValue<Student?>>((ref) {
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

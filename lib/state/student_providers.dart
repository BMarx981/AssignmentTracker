// selectedStudentIdProvider is a write-through provider: setting it calls
// /api/students/{id}/select on the server and then refreshes /api/data.
// selectedStudentProvider returns the Student from the most recent payload.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_models.dart';
import 'api_providers.dart';
import 'data_providers.dart';

class SelectedStudentIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  Future<void> select(String id) async {
    if (state == id) return;
    state = id;
    final client = await ref.read(apiClientProvider.future);
    await client.selectStudent(id);
    await ref.read(dataProvider.notifier).refresh();
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

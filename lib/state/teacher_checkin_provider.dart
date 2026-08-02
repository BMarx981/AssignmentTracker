// The teacher check-in list: every assignment the student flagged with
// "Remind me to ask teacher", grouped by course.
//
// Nothing new is persisted for this — the flag has always been stored as a
// comment thread matching [kTeacherCheckInNote], so the list is a pure
// projection over data that already exists (including flags set before this
// screen did).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:assignment_tracker_app/domain/assignment_situation.dart';
import 'package:assignment_tracker_app/domain/merged.dart';
import 'package:assignment_tracker_app/models/api_models.dart';
import 'priority_providers.dart';
import 'student_providers.dart';

class TeacherCheckIn {
  const TeacherCheckIn({required this.course, required this.items});
  final MergedCourse course;
  final List<MergedItem> items;
}

/// autoDispose for the same reason as the other derived providers — see the
/// note on [mergedCoursesProvider].
final teacherCheckInsProvider =
    Provider.autoDispose<List<TeacherCheckIn>>((ref) {
  final student = ref.watch(selectedStudentProvider).value;
  final courses = ref.watch(mergedCoursesProvider);
  if (student == null) return const [];

  final out = <TeacherCheckIn>[];
  for (final course in courses) {
    final flagged = course.items
        .where((it) => hasNote(
              student.comments[it.key] ?? const <CommentThread>[],
              kTeacherCheckInNote,
            ))
        .toList(growable: false);
    if (flagged.isNotEmpty) {
      out.add(TeacherCheckIn(course: course, items: flagged));
    }
  }
  return out;
});

/// Total flagged assignments, for the dashboard's badge.
final teacherCheckInCountProvider = Provider.autoDispose<int>((ref) {
  return ref
      .watch(teacherCheckInsProvider)
      .fold<int>(0, (sum, g) => sum + g.items.length);
});

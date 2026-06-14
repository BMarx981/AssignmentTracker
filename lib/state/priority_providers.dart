// Derived providers: merged courses for the current student, the ranked top-20
// priority list, and the grade-bands map. Recomputes when any upstream changes.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/merged.dart';
import '../domain/priority.dart';
import 'data_providers.dart';
import 'prefs_providers.dart';
import 'student_providers.dart';

class RankedItem {
  final MergedItem item;
  final MergedCourse course;
  final double score;
  const RankedItem(
      {required this.item, required this.course, required this.score});
}

/// The merged-course list for the currently selected student. Filters out
/// hidden courses, but does not yet apply the date range (consumers do that).
final mergedCoursesProvider = Provider<List<MergedCourse>>((ref) {
  final student = ref.watch(selectedStudentProvider).value;
  if (student == null) return const [];
  final hidden = ref
          .watch(hiddenCoursesProvider(student.studentId))
          .value ??
      const <String>{};
  return mergeData(student.canvas, student.synergy)
      .where((c) => !hidden.contains(c.name))
      .toList(growable: false);
});

final rankedAssignmentsProvider = Provider<List<RankedItem>>((ref) {
  final courses = ref.watch(mergedCoursesProvider);
  final studentAsync = ref.watch(selectedStudentProvider);
  final student = studentAsync.value;
  final rangeAsync = ref.watch(dateRangeProvider);
  final range = rangeAsync.value;
  if (student == null || range == null) return const [];
  final today = DateTime.now();
  final out = <RankedItem>[];
  for (final c in courses) {
    for (final it in c.items) {
      final s = priorityScore(
        item: it,
        course: c,
        today: today,
        thresholds: student.scoreThresholds,
        statusByKey: student.assignmentStatus,
        range: range,
      );
      if (s >= 0) out.add(RankedItem(item: it, course: c, score: s));
    }
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  return out;
});

final top20Provider = Provider<List<RankedItem>>((ref) {
  final ranked = ref.watch(rankedAssignmentsProvider);
  return ranked.take(20).toList(growable: false);
});

final gradeBandsProvider = Provider<dynamic>((ref) {
  // Re-export from the latest DataPayload for convenient widget access.
  return ref.watch(dataProvider).whenData((p) => p.gradeBands);
});

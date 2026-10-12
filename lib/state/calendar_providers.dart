// Calendar filters (one set per child) and the day → entries map built from
// the merged courses. Filters live in memory only: they reset on relaunch,
// which keeps a forgotten "hide Math" from silently hiding work next week.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:assignment_tracker_app/domain/calendar.dart';
import 'priority_providers.dart';
import 'student_providers.dart';

class CalendarFilterNotifier extends Notifier<CalendarFilter> {
  CalendarFilterNotifier(this.studentId);
  final String studentId;

  @override
  CalendarFilter build() => const CalendarFilter();

  void toggleCourse(String name) => state = state.toggleCourse(name);
  void toggleKind(CalendarKind k) => state = state.toggleKind(k);
  void toggleStatus(CalendarStatus s) => state = state.toggleStatus(s);
  void setHiddenCourses(Set<String> names) =>
      state = state.withHiddenCourses(names);
  void reset() => state = const CalendarFilter();
}

/// Keyed by student id, so each child keeps their own filters.
final calendarFilterProvider =
    NotifierProvider.family<CalendarFilterNotifier, CalendarFilter, String>(
  CalendarFilterNotifier.new,
);

/// The selected child's calendar. The family argument is a course name to
/// scope to one class, or '' for all of them.
///
/// autoDispose for the reason on [mergedCoursesProvider].
final calendarEntriesProvider = Provider.autoDispose
    .family<Map<String, List<CalendarEntry>>, String>((ref, onlyCourse) {
  final student = ref.watch(selectedStudentProvider).value;
  if (student == null) return const {};
  return buildCalendar(
    ref.watch(mergedCoursesProvider),
    filter: ref.watch(calendarFilterProvider(student.studentId)),
    today: DateTime.now(),
    onlyCourse: onlyCourse.isEmpty ? null : onlyCourse,
  );
});

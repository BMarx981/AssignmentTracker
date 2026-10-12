// What the calendar screen shows on each day, and the filters that narrow it.
//
// Two kinds of entry share a day: assignments (every MergedItem with a date,
// from either source) and Canvas calendar events. Assignments also land in one
// of four status groups — coarser than MergedItem.status on purpose, because
// a month grid needs answers a parent can read at a glance, not the dozen
// source-specific flags behind them.
//
// Filters are stored as what's *hidden*, so a class that appears mid-year (or
// a child's first fetch) shows up without anyone having to tick it.

import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:assignment_tracker_app/util/format.dart';
import 'merged.dart';
import 'priority.dart';

enum CalendarKind { assignments, events }

enum CalendarStatus {
  /// Overdue and not turned in, a zero, or Synergy's 50%-credit stand-in.
  missing,

  /// Not turned in, due today or later.
  upcoming,

  /// Turned in, no grade yet.
  waiting,

  /// Has a grade (or was excused).
  graded,
}

/// The status group for [item], judged against [today].
CalendarStatus calendarStatusOf(MergedItem item, DateTime today) {
  switch (item.status) {
    case 'zero_graded':
    case 'half_credit_missing':
      return CalendarStatus.missing;
    case 'missing':
      final d = item.date;
      if (d != null && d.compareTo(ymd(today)) >= 0) {
        return CalendarStatus.upcoming;
      }
      return CalendarStatus.missing;
    case 'submitted_pending':
    case 'not_graded':
      return CalendarStatus.waiting;
  }
  if (item.canvasStatus == 'submitted_pending') return CalendarStatus.waiting;
  // 'graded', Synergy's 'ok', 'excused'; 'unknown'/'other' only once scored.
  if (item.status == 'unknown' || item.status == 'other') {
    return hasRealGrade(item) ? CalendarStatus.graded : CalendarStatus.waiting;
  }
  return CalendarStatus.graded;
}

/// One thing on one day: an assignment or a Canvas event, never both.
class CalendarEntry {
  const CalendarEntry.assignment(this.course, MergedItem this.item, CalendarStatus this.status)
      : event = null;
  const CalendarEntry.event(this.course, CanvasEvent this.event)
      : item = null,
        status = null;

  final MergedCourse course;
  final MergedItem? item;
  final CanvasEvent? event;
  final CalendarStatus? status; // null for events

  CalendarKind get kind =>
      event != null ? CalendarKind.events : CalendarKind.assignments;
}

class CalendarFilter {
  const CalendarFilter({
    this.hiddenCourses = const {},
    this.hiddenKinds = const {},
    this.hiddenStatuses = const {},
  });

  final Set<String> hiddenCourses;
  final Set<CalendarKind> hiddenKinds;

  /// Only narrows assignments; events have no status.
  final Set<CalendarStatus> hiddenStatuses;

  bool get isDefault =>
      hiddenCourses.isEmpty && hiddenKinds.isEmpty && hiddenStatuses.isEmpty;

  /// [ignoreCourses] is for a calendar already scoped to one class, where the
  /// class filter from the all-classes view shouldn't hide that class.
  bool admits(CalendarEntry e, {bool ignoreCourses = false}) {
    if (!ignoreCourses && hiddenCourses.contains(e.course.name)) return false;
    if (hiddenKinds.contains(e.kind)) return false;
    final s = e.status;
    if (s != null && hiddenStatuses.contains(s)) return false;
    return true;
  }

  CalendarFilter toggleCourse(String name) => CalendarFilter(
        hiddenCourses: _toggle(hiddenCourses, name),
        hiddenKinds: hiddenKinds,
        hiddenStatuses: hiddenStatuses,
      );

  CalendarFilter toggleKind(CalendarKind k) => CalendarFilter(
        hiddenCourses: hiddenCourses,
        hiddenKinds: _toggle(hiddenKinds, k),
        hiddenStatuses: hiddenStatuses,
      );

  CalendarFilter toggleStatus(CalendarStatus s) => CalendarFilter(
        hiddenCourses: hiddenCourses,
        hiddenKinds: hiddenKinds,
        hiddenStatuses: _toggle(hiddenStatuses, s),
      );

  CalendarFilter withHiddenCourses(Set<String> names) => CalendarFilter(
        hiddenCourses: names,
        hiddenKinds: hiddenKinds,
        hiddenStatuses: hiddenStatuses,
      );

  static Set<T> _toggle<T>(Set<T> s, T v) =>
      s.contains(v) ? ({...s}..remove(v)) : {...s, v};
}

/// Every entry in [courses], keyed by local `YYYY-MM-DD`, narrowed by
/// [filter]. Pass [onlyCourse] for a single class's calendar.
///
/// Within a day, events come first (they're usually the bigger deal — a test,
/// a field trip), ordered by start time, then assignments by class.
Map<String, List<CalendarEntry>> buildCalendar(
  List<MergedCourse> courses, {
  required CalendarFilter filter,
  required DateTime today,
  String? onlyCourse,
}) {
  final out = <String, List<CalendarEntry>>{};
  void add(String day, CalendarEntry e) {
    if (filter.admits(e, ignoreCourses: onlyCourse != null)) {
      (out[day] ??= []).add(e);
    }
  }

  for (final c in courses) {
    if (onlyCourse != null && c.name != onlyCourse) continue;
    for (final it in c.items) {
      final d = it.date;
      if (d == null || d.length < 10) continue;
      add(d.substring(0, 10),
          CalendarEntry.assignment(c, it, calendarStatusOf(it, today)));
    }
    for (final ev in c.events) {
      for (final d in ev.days) {
        add(d, CalendarEntry.event(c, ev));
      }
    }
  }

  for (final list in out.values) {
    list.sort((a, b) {
      if (a.kind != b.kind) return a.kind == CalendarKind.events ? -1 : 1;
      if (a.event != null) {
        final at = a.event!.allDay ? null : a.event!.startAt;
        final bt = b.event!.allDay ? null : b.event!.startAt;
        if (at == null && bt == null) {
          return a.event!.title.compareTo(b.event!.title);
        }
        if (at == null) return -1; // all-day first
        if (bt == null) return 1;
        return at.compareTo(bt);
      }
      final byCourse = a.course.name.compareTo(b.course.name);
      return byCourse != 0 ? byCourse : a.item!.name.compareTo(b.item!.name);
    });
  }
  return out;
}

/// A stable color slot per class: alphabetical order, so a class keeps its
/// color across refreshes and between the all-classes and one-class views.
Map<String, int> courseColorSlots(List<MergedCourse> courses) {
  final names = courses.map((c) => c.name).toSet().toList()..sort();
  return {for (var i = 0; i < names.length; i++) names[i]: i};
}

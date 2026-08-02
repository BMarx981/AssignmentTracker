// Which days a streak is allowed to be broken on.
//
// The streak exists to build a school-week habit, so it has to be scored
// against the school week. Two kinds of day are skipped rather than counted:
//
//   * Weekends — nobody should lose a run for not doing homework on Saturday.
//   * Excused days — a sick day, a family trip, a day the parent decided
//     doesn't count. Set behind the parent gate, never by the student.
//
// "Skipped" is precise here: a skipped day neither extends the streak nor
// breaks it. The run closes over the gap as if the day weren't on the
// calendar. A skipped day pays nothing on its own — missing school is not an
// accomplishment — it just costs nothing.
//
// Doing something on a skipped day still counts. Opening the app on a Sunday
// earns its check-in and extends the run; the calendar only decides what
// happens when a day is *empty*.

import 'package:assignment_tracker_app/util/format.dart';

class StreakCalendar {
  const StreakCalendar({
    this.excusedDays = const <String>{},
    this.restDays = const {DateTime.saturday, DateTime.sunday},
  });

  /// `YYYY-MM-DD` local dates the parent has excused.
  final Set<String> excusedDays;

  /// Weekdays (`DateTime.monday`…) that never count against a run. Fixed to
  /// the weekend for now; a school on a different schedule would set this.
  final Set<int> restDays;

  /// Weekends only, nothing excused — the default before any parent has set
  /// anything up, and the calendar tests use as a baseline.
  static const standard = StreakCalendar();

  bool isRestDay(DateTime day) => restDays.contains(day.weekday);

  bool isExcused(DateTime day) => excusedDays.contains(ymd(day));

  /// True when an empty [day] should end the run. False for weekends and
  /// excused days, which the streak walks straight past.
  bool countsAgainstStreak(DateTime day) => !isRestDay(day) && !isExcused(day);

  StreakCalendar withExcused(Set<String> days) =>
      StreakCalendar(excusedDays: days, restDays: restDays);
}

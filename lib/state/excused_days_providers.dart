// Excused days and the streak calendar they feed.
//
// Writes here are parent-only, but the gate lives in the UI ([ParentGate]) —
// these providers assume the caller already passed it, the same way
// [AssignmentActions] assumes the student meant to tap the button.
//
// NOTE: Riverpod 3 API — the family notifier takes its argument through the
// constructor rather than a FamilyAsyncNotifier base class.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:assignment_tracker_app/domain/streak_calendar.dart';
import 'package:assignment_tracker_app/util/format.dart';
import 'api_providers.dart';
import 'student_providers.dart';

/// One excused day. The reason is for the parent's own records — nothing in
/// the streak math reads it.
class ExcusedDay {
  const ExcusedDay({required this.date, this.reason = ''});

  /// `YYYY-MM-DD`, local.
  final String date;
  final String reason;

  Map<String, dynamic> toJson() => {'date': date, 'reason': reason};
}

class ExcusedDaysNotifier extends AsyncNotifier<List<ExcusedDay>> {
  ExcusedDaysNotifier(this.studentId);

  final String studentId;

  @override
  Future<List<ExcusedDay>> build() async {
    final store = await ref.watch(localStoreProvider.future);
    return _parse(await store.readExcusedDays(studentId));
  }

  static List<ExcusedDay> _parse(Map<String, dynamic>? raw) {
    final days = (raw?['days'] as List?) ?? const [];
    final out = <ExcusedDay>[];
    for (final d in days) {
      if (d is! Map) continue;
      final date = d['date'] as String?;
      if (date == null || date.isEmpty) continue;
      out.add(ExcusedDay(date: date, reason: d['reason'] as String? ?? ''));
    }
    // Newest first — a parent excusing a day is almost always looking at
    // something recent.
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  Future<void> excuse(DateTime day, {String reason = ''}) async {
    final date = ymd(day);
    final current = state.value ?? await future;
    if (current.any((d) => d.date == date)) return;
    await _write([
      ...current,
      ExcusedDay(date: date, reason: reason.trim()),
    ]);
  }

  Future<void> unexcuse(String date) async {
    final current = state.value ?? await future;
    await _write(current.where((d) => d.date != date).toList());
  }

  Future<void> _write(List<ExcusedDay> days) async {
    final sorted = [...days]..sort((a, b) => b.date.compareTo(a.date));
    state = AsyncData(sorted);
    final store = await ref.read(localStoreProvider.future);
    await store.writeExcusedDays(studentId, {
      'days': [for (final d in sorted) d.toJson()],
    });
  }
}

final excusedDaysProvider = AsyncNotifierProvider.family<ExcusedDaysNotifier,
    List<ExcusedDay>, String>(ExcusedDaysNotifier.new);

/// The selected student's excused days.
final currentExcusedDaysProvider =
    Provider.autoDispose<AsyncValue<List<ExcusedDay>>>((ref) {
  final studentId = ref.watch(selectedStudentProvider).value?.studentId;
  if (studentId == null) return const AsyncData(<ExcusedDay>[]);
  return ref.watch(excusedDaysProvider(studentId));
});

/// The rules the streak is scored against. Weekends are always off; excused
/// days come from the parent gate. Falls back to weekends-only while the file
/// is still loading, which is the right answer for every student who has
/// never had a day excused.
final streakCalendarProvider = Provider.autoDispose<StreakCalendar>((ref) {
  final excused = ref.watch(currentExcusedDaysProvider).value;
  if (excused == null || excused.isEmpty) return StreakCalendar.standard;
  return StreakCalendar(
    excusedDays: {for (final d in excused) d.date},
  );
});

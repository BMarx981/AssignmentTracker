// User prefs persisted to shared_preferences:
//   - hidden_courses_<studentId>   : List<String>
//   - date_range_start / date_range_end : YYYY-MM-DD strings
//
// Plus a Riverpod-friendly cache of the SharedPreferences instance.
//
// NOTE: Riverpod 3 API — family notifiers receive the arg via constructor,
// not via a FamilyAsyncNotifier base class.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/priority.dart';

final sharedPrefsProvider = FutureProvider<SharedPreferences>((_) async {
  return SharedPreferences.getInstance();
});

String _hiddenKey(String studentId) => 'hidden_courses_$studentId';

class HiddenCoursesNotifier extends AsyncNotifier<Set<String>> {
  HiddenCoursesNotifier(this.studentId);
  final String studentId;

  @override
  Future<Set<String>> build() async {
    final prefs = await ref.watch(sharedPrefsProvider.future);
    return (prefs.getStringList(_hiddenKey(studentId)) ?? const []).toSet();
  }

  Future<void> toggle(String courseName) async {
    final cur = (state.value ?? <String>{}).toSet();
    if (!cur.add(courseName)) cur.remove(courseName);
    state = AsyncData(cur);
    final prefs = await ref.read(sharedPrefsProvider.future);
    await prefs.setStringList(_hiddenKey(studentId), cur.toList());
  }
}

final hiddenCoursesProvider =
    AsyncNotifierProvider.family<HiddenCoursesNotifier, Set<String>, String>(
        HiddenCoursesNotifier.new);

class DateRangeNotifier extends AsyncNotifier<DateRange> {
  @override
  Future<DateRange> build() async {
    final prefs = await ref.watch(sharedPrefsProvider.future);
    final s = prefs.getString('date_range_start');
    final e = prefs.getString('date_range_end');
    if (s == null || e == null) {
      // Default: 1 month back, 1 month forward (matches markingPeriodDefaults
      // fallback in dashboard.html when no Canvas grading period is known).
      final today = DateTime.now();
      return DateRange(
        start: DateTime(today.year, today.month - 1, today.day),
        end: DateTime(today.year, today.month + 1, today.day),
      );
    }
    return DateRange(
      start: DateTime.parse('${s}T00:00:00'),
      end: DateTime.parse('${e}T00:00:00'),
    );
  }

  Future<void> setRange(DateTime start, DateTime end) async {
    state = AsyncData(DateRange(start: start, end: end));
    final prefs = await ref.read(sharedPrefsProvider.future);
    await prefs.setString(
        'date_range_start', start.toIso8601String().substring(0, 10));
    await prefs.setString(
        'date_range_end', end.toIso8601String().substring(0, 10));
  }

  Future<void> reset() async {
    final prefs = await ref.read(sharedPrefsProvider.future);
    await prefs.remove('date_range_start');
    await prefs.remove('date_range_end');
    ref.invalidateSelf();
  }
}

final dateRangeProvider =
    AsyncNotifierProvider<DateRangeNotifier, DateRange>(DateRangeNotifier.new);

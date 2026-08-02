// Rewards state: the per-student ledger, the award entry point, and the
// one-shot feed the celebration overlay listens to.
//
// The ledger is keyed by student and kept alive (no autoDispose) because
// awards are fired from providers, not widgets — `AssignmentActions` calls
// `award()` with nothing on screen listening, and an autoDispose family would
// tear the notifier down between the read and the write.
//
// NOTE: Riverpod 3 API — the family notifier takes its argument through the
// constructor rather than a FamilyAsyncNotifier base class.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:assignment_tracker_app/domain/rewards.dart';
import 'package:assignment_tracker_app/domain/streak_calendar.dart';
import 'package:assignment_tracker_app/util/format.dart';
import 'api_providers.dart';
import 'excused_days_providers.dart';
import 'student_providers.dart';

class RewardsNotifier extends AsyncNotifier<RewardLedger> {
  RewardsNotifier(this.studentId);

  final String studentId;

  @override
  Future<RewardLedger> build() async {
    final store = await ref.watch(localStoreProvider.future);
    return RewardLedger.fromJson(await store.readRewards(studentId));
  }

  /// Read rather than watched: the excused days only affect how a streak is
  /// *scored*, so a parent excusing a day shouldn't force the ledger itself to
  /// be re-read from disk.
  Future<StreakCalendar> _calendar() async {
    final excused = await ref.read(excusedDaysProvider(studentId).future);
    return StreakCalendar(excusedDays: {for (final d in excused) d.date});
  }

  /// Records [kind] against [id], persists, and returns what changed.
  ///
  /// Returns null when [id] was already awarded, so callers can treat "no
  /// outcome" as "stay quiet" without tracking their own history.
  Future<RewardOutcome?> award({
    required RewardKind kind,
    required String id,
    required String label,
    int? points,
    DateTime? at,
  }) async {
    final before = state.value ?? await future;
    final result = applyReward(
      before,
      RewardEvent(
        id: id,
        kind: kind,
        points: points ?? kind.points,
        at: (at ?? DateTime.now()).toUtc(),
        label: label,
      ),
      now: at,
      calendar: await _calendar(),
    );
    if (result == null) return null;

    state = AsyncData(result.ledger);
    final store = await ref.read(localStoreProvider.future);
    await store.writeRewards(studentId, result.ledger.toJson());
    return result.outcome;
  }

  /// Pays for opening the app today, at the rate the current streak has
  /// earned. Keyed on the local date, so it fires once a day no matter how
  /// many times the app is launched, resumed, or navigated around — callers
  /// are free to call it on every lifecycle event.
  Future<RewardOutcome?> recordVisit({DateTime? now}) {
    // Launch and resume can land within the same frame. Without this, both
    // would read a ledger that has no visit yet and both would celebrate; the
    // ledger would still hold one event (same id), but the student would see
    // two toasts.
    final inFlight = _visitInFlight;
    if (inFlight != null) return inFlight;
    final pending = _recordVisit(now: now);
    _visitInFlight = pending;
    return pending.whenComplete(() {
      if (identical(_visitInFlight, pending)) _visitInFlight = null;
    });
  }

  Future<RewardOutcome?>? _visitInFlight;

  Future<RewardOutcome?> _recordVisit({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final ledger = state.value ?? await future;
    final id = 'visit:${ymd(today)}';
    if (ledger.hasEvent(id)) return null;

    // Priced off the run this check-in is joining, which is why the weekend
    // and excused rules have to be in hand before the payout is decided.
    final day = ledger.streakAfterActivityOn(today, calendar: await _calendar());
    return award(
      kind: RewardKind.visit,
      id: id,
      label: 'Day $day check-in',
      points: visitPoints(day),
      at: today,
    );
  }
}

final rewardsProvider =
    AsyncNotifierProvider.family<RewardsNotifier, RewardLedger, String>(
        RewardsNotifier.new);

/// A ledger together with the calendar it has to be scored against.
///
/// These travel as a pair on purpose. A streak read off a bare ledger silently
/// uses the default calendar and reports a run the parent already excused as
/// broken, so the UI is handed both or neither.
class RewardsView {
  const RewardsView({required this.ledger, required this.calendar});

  final RewardLedger ledger;
  final StreakCalendar calendar;

  static const empty = RewardsView(
    ledger: RewardLedger.empty,
    calendar: StreakCalendar.standard,
  );

  int get streak => ledger.currentStreak(calendar: calendar);
  int get bestStreak => ledger.bestStreak(calendar: calendar);
  List<RewardBadge> get badges => ledger.badges(calendar: calendar);
}

/// The selected student's ledger and calendar, or empties before a student
/// resolves. autoDispose for the same reason as the other derived providers —
/// see the note on [selectedStudentProvider].
final currentRewardsProvider =
    Provider.autoDispose<AsyncValue<RewardsView>>((ref) {
  final studentId = ref.watch(selectedStudentProvider).value?.studentId;
  if (studentId == null) return const AsyncData(RewardsView.empty);
  final calendar = ref.watch(streakCalendarProvider);
  return ref
      .watch(rewardsProvider(studentId))
      .whenData((ledger) => RewardsView(ledger: ledger, calendar: calendar));
});

/// Awards against whichever student is selected. Everything that hands out
/// points goes through here rather than reaching for the family directly, so
/// no call site has to know how the student id is resolved.
class RewardService {
  RewardService(this._ref);

  final Ref _ref;

  Future<RewardOutcome?> award({
    required RewardKind kind,
    required String id,
    required String label,
  }) =>
      _run((n) => n.award(kind: kind, id: id, label: label));

  /// Pays for showing up today. Safe to call on every launch and resume —
  /// [RewardsNotifier.recordVisit] is keyed on the date and no-ops once the
  /// day is already banked.
  Future<RewardOutcome?> recordVisit() => _run((n) => n.recordVisit());

  Future<RewardOutcome?> _run(
    Future<RewardOutcome?> Function(RewardsNotifier) op,
  ) async {
    final studentId = _ref.read(selectedStudentProvider).value?.studentId;
    if (studentId == null) return null;
    final outcome = await op(_ref.read(rewardsProvider(studentId).notifier));
    if (outcome != null) {
      _ref.read(rewardFeedProvider.notifier).push(outcome);
    }
    return outcome;
  }
}

final rewardServiceProvider =
    Provider<RewardService>((ref) => RewardService(ref));

/// The most recent unshown award. [RewardHost] watches this, plays the
/// celebration, then clears it — so the animation fires exactly once no matter
/// which screen was on top when the points landed.
class RewardFeedNotifier extends Notifier<RewardOutcome?> {
  @override
  RewardOutcome? build() => null;

  void push(RewardOutcome outcome) => state = outcome;

  void clear(RewardOutcome outcome) {
    if (identical(state, outcome)) state = null;
  }
}

final rewardFeedProvider =
    NotifierProvider<RewardFeedNotifier, RewardOutcome?>(
        RewardFeedNotifier.new);

// The rewards ledger: an append-only log of things the student did, plus the
// pure derivations the UI renders off it (points, level, streak, badges).
//
// Deliberately append-only and dedupe-keyed. Every award carries an `id` built
// from the action and its subject — `turnedIn:<assignmentKey>` — so unmarking
// and re-marking the same assignment can't farm points, and clearing a status
// never takes points away. Rewards only ever go up; that's the whole point of
// them.
//
// Points are snapshotted onto the event at award time rather than recomputed
// from [RewardKind.points], so retuning the payouts later doesn't silently
// rewrite a student's history.
//
// Nothing in here imports Flutter — badges carry an emoji rather than an
// IconData so the whole file stays testable as plain Dart.

import 'package:assignment_tracker_app/util/format.dart';
import 'streak_calendar.dart';

/// What earned the points.
enum RewardKind {
  /// Opened the app on a day it hadn't been opened yet. Pays for the habit
  /// itself — a student who never opens this can't use any of the rest of it.
  visit,

  /// Committed to a date for something not done yet.
  planned,

  /// Marked done but not handed in.
  finished,

  /// Marked turned in — the one that actually clears the catch-up list.
  turnedIn,

  /// Sent a teacher an email from the check-in screen.
  teacherEmail,
}

extension RewardKindX on RewardKind {
  /// Payout for a fresh award of this kind. Scaled by how much the action
  /// actually moves the needle: planning is cheap, emailing a teacher is the
  /// one most students avoid, so it pays the most.
  ///
  /// [RewardKind.visit] is the base rate only — the real payout escalates with
  /// the streak, see [visitPoints].
  int get points => switch (this) {
        RewardKind.visit => 3,
        RewardKind.planned => 2,
        RewardKind.finished => 5,
        RewardKind.turnedIn => 10,
        RewardKind.teacherEmail => 15,
      };

  String get emoji => switch (this) {
        RewardKind.visit => '👋',
        RewardKind.planned => '🗓️',
        RewardKind.finished => '📚',
        RewardKind.turnedIn => '✅',
        RewardKind.teacherEmail => '👍',
      };

  /// Past-tense label for the activity feed.
  String get verb => switch (this) {
        RewardKind.visit => 'Checked in',
        RewardKind.planned => 'Planned',
        RewardKind.finished => 'Finished',
        RewardKind.turnedIn => 'Turned in',
        RewardKind.teacherEmail => 'Emailed about',
      };

  /// Rotating congratulations, so the tenth one of the day doesn't read like
  /// a form letter. Picked by count rather than at random so it's testable.
  List<String> get headlines => switch (this) {
        // Index 0 is the very first check-in a student ever sees, so it has
        // to work for someone who has never been here — "welcome back" waits
        // for the second one.
        RewardKind.visit => const [
            'Good to see you.',
            'Welcome back.',
            "You're keeping this up.",
            'Back again. Nice.',
          ],
        RewardKind.planned => const [
            "Nice — that's a plan.",
            'Future you says thanks.',
            "It's on the calendar now.",
          ],
        RewardKind.finished => const [
            'Done! Now go hand it in.',
            "That's the hard part over.",
            'Finished. Nice work.',
          ],
        RewardKind.turnedIn => const [
            'Turned in. Nice work.',
            'One less thing.',
            "That's how it's done.",
            'Off your plate.',
          ],
        RewardKind.teacherEmail => const [
            'Nice — asking is the hard part.',
            'Message sent. Well played.',
            'Reaching out counts for a lot.',
          ],
      };

  static RewardKind? parse(String? raw) {
    for (final k in RewardKind.values) {
      if (k.name == raw) return k;
    }
    return null;
  }
}

/// What a daily check-in pays on day [streakDay] of a run.
///
/// It escalates on purpose. A flat daily payout makes each individual day
/// disposable; a rate that climbs and resets makes the streak itself the thing
/// worth protecting, which is the actual habit being built. The ceiling is low
/// enough that showing up never out-earns doing the work.
int visitPoints(int streakDay) {
  if (streakDay >= 7) return 8;
  if (streakDay >= 3) return 5;
  return 3;
}

/// Tomorrow's check-in payout, given today's streak. Drives the "come back
/// tomorrow for +N" nudge.
int nextVisitPoints(int currentStreak) => visitPoints(currentStreak + 1);

/// The most a check-in can ever pay. Past this the streak stops buying a
/// bigger number and only buys not losing the one you have.
final int maxVisitPoints = visitPoints(1000);

/// One awarded action. Immutable once written.
class RewardEvent {
  const RewardEvent({
    required this.id,
    required this.kind,
    required this.points,
    required this.at,
    required this.label,
  });

  /// Dedupe key. Two awards with the same id are the same achievement.
  final String id;
  final RewardKind kind;
  final int points;

  /// When it was earned, in UTC.
  final DateTime at;

  /// What it was for — assignment name, or course name for a teacher email.
  final String label;

  /// Returns null for an event whose kind this build doesn't know, so a file
  /// written by a newer version degrades to "ignore it" rather than crashing.
  static RewardEvent? fromJson(Map<String, dynamic> j) {
    final kind = RewardKindX.parse(j['kind'] as String?);
    final at = DateTime.tryParse('${j['at']}');
    final id = j['id'] as String?;
    if (kind == null || at == null || id == null || id.isEmpty) return null;
    return RewardEvent(
      id: id,
      kind: kind,
      points: (j['points'] as num?)?.toInt() ?? kind.points,
      at: at.toUtc(),
      label: j['label'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'points': points,
        'at': at.toUtc().toIso8601String(),
        'label': label,
      };
}

/// A rank the student climbs through. [minPoints] is the entry threshold.
class RewardLevel {
  const RewardLevel({
    required this.index,
    required this.name,
    required this.emoji,
    required this.minPoints,
  });

  final int index;
  final String name;
  final String emoji;
  final int minPoints;
}

/// Thresholds widen as they go so early progress feels quick and later levels
/// stay worth chasing.
const kRewardLevels = <RewardLevel>[
  RewardLevel(index: 0, name: 'Getting started', emoji: '🌱', minPoints: 0),
  RewardLevel(index: 1, name: 'Warming up', emoji: '🔆', minPoints: 50),
  RewardLevel(index: 2, name: 'On a roll', emoji: '🚀', minPoints: 150),
  RewardLevel(index: 3, name: 'Locked in', emoji: '🎯', minPoints: 350),
  RewardLevel(index: 4, name: 'Unstoppable', emoji: '⚡', minPoints: 700),
  RewardLevel(index: 5, name: 'Legend', emoji: '👑', minPoints: 1200),
];

/// A milestone, with enough progress detail to render a locked badge as
/// "3 / 5" rather than a blank slot.
class RewardBadge {
  const RewardBadge({
    required this.id,
    required this.emoji,
    required this.name,
    required this.description,
    required this.progress,
    required this.target,
  });

  final String id;
  final String emoji;
  final String name;
  final String description;
  final int progress;
  final int target;

  bool get earned => progress >= target;

  /// 0..1, for the locked-badge meter.
  double get fraction =>
      target <= 0 ? 1 : (progress / target).clamp(0.0, 1.0).toDouble();
}

/// The whole ledger plus everything derived from it.
class RewardLedger {
  const RewardLedger(this.events);

  /// Oldest first.
  final List<RewardEvent> events;

  static const empty = RewardLedger(<RewardEvent>[]);

  int get totalPoints => events.fold(0, (sum, e) => sum + e.points);

  bool get isEmpty => events.isEmpty;

  int countOf(RewardKind kind) =>
      events.where((e) => e.kind == kind).length;

  bool hasEvent(String id) => events.any((e) => e.id == id);

  /// Most recent first — what the activity feed shows.
  List<RewardEvent> get recent =>
      events.reversed.toList(growable: false);

  RewardLedger add(RewardEvent event) =>
      RewardLedger([...events, event]);

  // ---------- level ----------

  RewardLevel get level {
    var current = kRewardLevels.first;
    for (final l in kRewardLevels) {
      if (totalPoints >= l.minPoints) current = l;
    }
    return current;
  }

  /// Null once the top level is reached.
  RewardLevel? get nextLevel {
    final i = level.index + 1;
    return i < kRewardLevels.length ? kRewardLevels[i] : null;
  }

  int get pointsToNextLevel {
    final next = nextLevel;
    return next == null ? 0 : next.minPoints - totalPoints;
  }

  /// How far through the current level, 0..1. Full bar at the top level.
  double get levelProgress {
    final next = nextLevel;
    if (next == null) return 1;
    final span = next.minPoints - level.minPoints;
    if (span <= 0) return 1;
    return ((totalPoints - level.minPoints) / span).clamp(0.0, 1.0).toDouble();
  }

  // ---------- streak ----------

  /// Local calendar days that have at least one event. Since opening the app
  /// awards a [RewardKind.visit], this is in practice "days the student showed
  /// up", which is exactly what the streak should measure.
  Set<String> get _activeDays =>
      events.map((e) => ymd(e.at.toLocal())).toSet();

  /// Whether anything at all was recorded on [day]'s local calendar date.
  bool hasActivityOn(DateTime day) => _activeDays.contains(ymd(day));

  /// The streak this ledger would be on after recording something on [day].
  /// Used to price a check-in before it is written.
  int streakAfterActivityOn(DateTime day, {StreakCalendar? calendar}) {
    if (hasActivityOn(day)) return currentStreak(now: day, calendar: calendar);
    return currentStreak(now: day, calendar: calendar) + 1;
  }

  /// How many days the current run is worth, walking backwards from today.
  ///
  /// Three kinds of day, per [StreakCalendar]:
  ///   * active — counts, keep walking
  ///   * empty but skippable (weekend, excused) — doesn't count, keep walking
  ///   * empty and required — the run ended here
  ///
  /// Today is always skippable regardless: the day isn't over, so opening the
  /// app in the morning must not show a streak that already looks lost.
  int currentStreak({DateTime? now, StreakCalendar? calendar}) {
    final cal = calendar ?? StreakCalendar.standard;
    final days = _activeDays;
    if (days.isEmpty) return 0;

    // Walking back forever would be the only way to fall off the end, so stop
    // once the cursor passes the oldest thing on the ledger.
    final oldest = _startOfDay(
      events.map((e) => e.at.toLocal()).reduce((a, b) => a.isBefore(b) ? a : b),
    );

    var cursor = _startOfDay(now ?? DateTime.now());
    var count = 0;
    var isToday = true;

    while (!cursor.isBefore(oldest)) {
      if (days.contains(ymd(cursor))) {
        count++;
      } else if (!isToday && cal.countsAgainstStreak(cursor)) {
        break;
      }
      isToday = false;
      cursor = _startOfDay(cursor.subtract(const Duration(days: 1)));
    }
    return count;
  }

  /// Longest run ever, scored by the same rules — two active days count as
  /// consecutive when everything between them was a weekend or excused.
  int bestStreak({StreakCalendar? calendar}) {
    final cal = calendar ?? StreakCalendar.standard;
    final days = (_activeDays.toList()..sort())
        .map((d) => DateTime.parse('${d}T00:00:00'))
        .toList(growable: false);
    if (days.isEmpty) return 0;

    var best = 1;
    var run = 1;
    for (var i = 1; i < days.length; i++) {
      run = _bridged(days[i - 1], days[i], cal) ? run + 1 : 1;
      if (run > best) best = run;
    }
    return best;
  }

  /// Whether every day strictly between [from] and [to] was skippable, so the
  /// two active days belong to one run.
  static bool _bridged(DateTime from, DateTime to, StreakCalendar cal) {
    var cursor = _startOfDay(from.add(const Duration(days: 1)));
    while (cursor.isBefore(to)) {
      if (cal.countsAgainstStreak(cursor)) return false;
      cursor = _startOfDay(cursor.add(const Duration(days: 1)));
    }
    return true;
  }

  // ---------- badges ----------

  /// Every badge, earned or not, in display order.
  List<RewardBadge> badges({DateTime? now, StreakCalendar? calendar}) {
    final streak = currentStreak(now: now, calendar: calendar);
    final bestRun = bestStreak(calendar: calendar);
    // A streak badge should stay earned after the streak lapses, so it scores
    // off the best run ever rather than the live one.
    final streakScore = streak > bestRun ? streak : bestRun;
    return [
      RewardBadge(
        id: 'first-step',
        emoji: '🌱',
        name: 'First step',
        description: 'Record anything at all.',
        progress: events.length.clamp(0, 1),
        target: 1,
      ),
      RewardBadge(
        id: 'showed-up-10',
        emoji: '👋',
        name: 'Showing up',
        description: 'Open the app on 10 different days.',
        progress: countOf(RewardKind.visit),
        target: 10,
      ),
      RewardBadge(
        id: 'turned-in-5',
        emoji: '✅',
        name: 'Five down',
        description: 'Turn in 5 assignments.',
        progress: countOf(RewardKind.turnedIn),
        target: 5,
      ),
      RewardBadge(
        id: 'turned-in-25',
        emoji: '🏅',
        name: 'Quarter century',
        description: 'Turn in 25 assignments.',
        progress: countOf(RewardKind.turnedIn),
        target: 25,
      ),
      RewardBadge(
        id: 'turned-in-50',
        emoji: '🏆',
        name: 'Half a hundred',
        description: 'Turn in 50 assignments.',
        progress: countOf(RewardKind.turnedIn),
        target: 50,
      ),
      RewardBadge(
        id: 'planner-10',
        emoji: '🗓️',
        name: 'Planner',
        description: 'Put 10 assignments on the calendar.',
        progress: countOf(RewardKind.planned),
        target: 10,
      ),
      RewardBadge(
        id: 'spoke-up-1',
        emoji: '👍',
        name: 'Spoke up',
        description: 'Email a teacher about an assignment.',
        progress: countOf(RewardKind.teacherEmail),
        target: 1,
      ),
      RewardBadge(
        id: 'spoke-up-5',
        emoji: '📣',
        name: 'Self-advocate',
        description: 'Email teachers 5 times.',
        progress: countOf(RewardKind.teacherEmail),
        target: 5,
      ),
      RewardBadge(
        id: 'streak-3',
        emoji: '🔥',
        name: 'Three in a row',
        description: 'Do something 3 days running.',
        progress: streakScore,
        target: 3,
      ),
      RewardBadge(
        id: 'streak-7',
        emoji: '⚡',
        name: 'Full week',
        description: 'Do something 7 days running.',
        progress: streakScore,
        target: 7,
      ),
      RewardBadge(
        id: 'streak-30',
        emoji: '⭐',
        name: 'Month straight',
        description: 'Show up 30 days running.',
        progress: streakScore,
        target: 30,
      ),
      RewardBadge(
        id: 'points-500',
        emoji: '💎',
        name: 'Five hundred',
        description: 'Bank 500 points.',
        progress: totalPoints,
        target: 500,
      ),
    ];
  }

  Set<String> earnedBadgeIds({DateTime? now, StreakCalendar? calendar}) =>
      badges(now: now, calendar: calendar)
          .where((b) => b.earned)
          .map((b) => b.id)
          .toSet();

  // ---------- json ----------

  static RewardLedger fromJson(Map<String, dynamic>? j) {
    final raw = (j?['events'] as List?) ?? const [];
    final events = <RewardEvent>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final parsed = RewardEvent.fromJson(e.cast<String, dynamic>());
      if (parsed != null) events.add(parsed);
    }
    events.sort((a, b) => a.at.compareTo(b.at));
    return RewardLedger(events);
  }

  Map<String, dynamic> toJson() => {
        'events': [for (final e in events) e.toJson()],
      };
}

/// What one award changed — the payload the celebration overlay renders.
class RewardOutcome {
  const RewardOutcome({
    required this.event,
    required this.headline,
    required this.totalPoints,
    required this.streak,
    this.newBadges = const [],
    this.newLevel,
  });

  final RewardEvent event;
  final String headline;
  final int totalPoints;
  final int streak;

  /// Badges crossed by this award. Usually empty.
  final List<RewardBadge> newBadges;

  /// Non-null only when this award pushed the student into a new level.
  final RewardLevel? newLevel;

  /// Milestones get the bigger treatment (confetti, longer hold).
  bool get isMilestone => newBadges.isNotEmpty || newLevel != null;
}

/// Applies [event] to [before], returning the new ledger and what changed.
/// Returns null when the event was already awarded — the caller should stay
/// silent rather than re-congratulate.
({RewardLedger ledger, RewardOutcome outcome})? applyReward(
  RewardLedger before,
  RewardEvent event, {
  DateTime? now,
  StreakCalendar? calendar,
}) {
  if (before.hasEvent(event.id)) return null;

  final after = before.add(event);
  final earnedBefore = before.earnedBadgeIds(now: now, calendar: calendar);
  final newBadges = after
      .badges(now: now, calendar: calendar)
      .where((b) => b.earned && !earnedBefore.contains(b.id))
      .toList(growable: false);

  final headlines = event.kind.headlines;
  final headline = headlines[before.countOf(event.kind) % headlines.length];

  return (
    ledger: after,
    outcome: RewardOutcome(
      event: event,
      headline: headline,
      totalPoints: after.totalPoints,
      streak: after.currentStreak(now: now, calendar: calendar),
      newBadges: newBadges,
      newLevel:
          after.level.index > before.level.index ? after.level : null,
    ),
  );
}

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

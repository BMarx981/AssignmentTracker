// Dates here are fixed to a known week rather than offset from `now`, because
// the streak is scored against the school calendar — a relative offset would
// land on a weekend or a weekday depending on the day the suite runs, and the
// weekend rule is exactly what several of these are checking.
//
//   Mon 14 · Tue 15 · Wed 16 · Thu 17 · Fri 18 · Sat 19 · Sun 20 · Mon 21 ·
//   Tue 22   — all September 2026.

import 'package:flutter_test/flutter_test.dart';

import 'package:assignment_tracker_app/domain/rewards.dart';
import 'package:assignment_tracker_app/domain/streak_calendar.dart';

/// Local noon on the given day of September 2026.
DateTime _at(int day) => DateTime(2026, 9, day, 12);

RewardEvent _ev(
  String id,
  RewardKind kind, {
  int on = 14,
  String label = 'Thing',
}) =>
    RewardEvent(
      id: id,
      kind: kind,
      points: kind.points,
      at: _at(on).toUtc(),
      label: label,
    );

RewardLedger _ledgerOf(List<RewardEvent> events) => RewardLedger(events);

StreakCalendar _excusing(List<int> septemberDays) => StreakCalendar(
      excusedDays: {
        for (final d in septemberDays) '2026-09-${d.toString().padLeft(2, '0')}',
      },
    );

void main() {
  group('points and levels', () {
    test('total is the sum of the points snapshotted on each event', () {
      final ledger = _ledgerOf([
        _ev('a', RewardKind.planned),
        _ev('b', RewardKind.turnedIn),
        _ev('c', RewardKind.teacherEmail),
      ]);
      expect(ledger.totalPoints, 2 + 10 + 15);
    });

    test('an event keeps its recorded points even if the payout changes', () {
      final ledger = _ledgerOf([
        RewardEvent(
          id: 'legacy',
          kind: RewardKind.turnedIn,
          points: 99,
          at: _at(14).toUtc(),
          label: 'Old payout',
        ),
      ]);
      expect(ledger.totalPoints, 99);
    });

    test('level climbs with the total and reports the gap to the next one', () {
      final ledger = _ledgerOf([
        for (var i = 0; i < 6; i++)
          _ev('t$i', RewardKind.turnedIn, on: 14 + i),
      ]);
      expect(ledger.totalPoints, 60);
      expect(ledger.level.name, 'Warming up');
      expect(ledger.nextLevel?.name, 'On a roll');
      expect(ledger.pointsToNextLevel, 90);
      expect(ledger.levelProgress, closeTo(0.1, 0.001));
    });

    test('the top level has no next and a full bar', () {
      final ledger = _ledgerOf([
        RewardEvent(
          id: 'huge',
          kind: RewardKind.turnedIn,
          points: 5000,
          at: _at(14).toUtc(),
          label: '',
        ),
      ]);
      expect(ledger.level.name, 'Legend');
      expect(ledger.nextLevel, isNull);
      expect(ledger.levelProgress, 1);
      expect(ledger.pointsToNextLevel, 0);
    });
  });

  group('streak', () {
    test('counts back through consecutive days ending today', () {
      final ledger = _ledgerOf([
        _ev('a', RewardKind.turnedIn, on: 16),
        _ev('b', RewardKind.planned, on: 15),
        _ev('c', RewardKind.turnedIn, on: 14),
      ]);
      expect(ledger.currentStreak(now: _at(16)), 3);
    });

    test('survives a day with nothing done yet, ending yesterday', () {
      final ledger = _ledgerOf([
        _ev('a', RewardKind.turnedIn, on: 15),
        _ev('b', RewardKind.turnedIn, on: 14),
      ]);
      expect(ledger.currentStreak(now: _at(16)), 2);
    });

    test('breaks once a school day passes with nothing recorded', () {
      final ledger = _ledgerOf([
        _ev('a', RewardKind.turnedIn, on: 15),
        _ev('b', RewardKind.turnedIn, on: 14),
      ]);
      // Wed the 16th was a school day and nothing happened on it.
      expect(ledger.currentStreak(now: _at(17)), 0);
    });

    test('several events in one day still count as one day', () {
      final ledger = _ledgerOf([
        _ev('a', RewardKind.turnedIn, on: 16),
        _ev('b', RewardKind.planned, on: 16),
        _ev('c', RewardKind.finished, on: 16),
      ]);
      expect(ledger.currentStreak(now: _at(16)), 1);
    });

    test('an empty ledger has no streak', () {
      expect(RewardLedger.empty.currentStreak(), 0);
      expect(RewardLedger.empty.bestStreak(), 0);
    });
  });

  group('weekends', () {
    test('an empty weekend does not break a run', () {
      final ledger = _ledgerOf([
        _ev('a', RewardKind.turnedIn, on: 18), // Fri
        _ev('b', RewardKind.turnedIn, on: 17), // Thu
      ]);
      // Mon is today, so it gets the same grace any today does; Sat and Sun
      // are skipped outright.
      expect(ledger.currentStreak(now: _at(21)), 2);
    });

    test('missing the Monday after does break it', () {
      final ledger = _ledgerOf([
        _ev('a', RewardKind.turnedIn, on: 18), // Fri
        _ev('b', RewardKind.turnedIn, on: 17), // Thu
      ]);
      // By Tuesday, Monday is a school day that came and went empty.
      expect(ledger.currentStreak(now: _at(22)), 0);
    });

    test('doing something on a weekend still counts toward the run', () {
      final ledger = _ledgerOf([
        _ev('a', RewardKind.visit, on: 21), // Mon
        _ev('b', RewardKind.visit, on: 19), // Sat
        _ev('c', RewardKind.visit, on: 18), // Fri
      ]);
      // Sun is empty and skipped; Sat was worked and counts.
      expect(ledger.currentStreak(now: _at(21)), 3);
    });

    test('a full school week off is still a break', () {
      final ledger = _ledgerOf([_ev('a', RewardKind.turnedIn, on: 14)]);
      expect(ledger.currentStreak(now: _at(21)), 0);
    });

    test('best streak bridges a weekend the same way', () {
      final ledger = _ledgerOf([
        _ev('a', RewardKind.turnedIn, on: 17), // Thu
        _ev('b', RewardKind.turnedIn, on: 18), // Fri
        _ev('c', RewardKind.turnedIn, on: 21), // Mon
      ]);
      expect(ledger.bestStreak(), 3);
      // With no rest days configured, the same three days read as two runs.
      expect(ledger.bestStreak(calendar: const StreakCalendar(restDays: {})), 2);
    });
  });

  group('excused days', () {
    final ledger = _ledgerOf([
      _ev('a', RewardKind.turnedIn, on: 17), // Thu
      _ev('b', RewardKind.turnedIn, on: 15), // Tue
      _ev('c', RewardKind.turnedIn, on: 14), // Mon
    ]);

    test('a missed school day breaks the run when it is not excused', () {
      expect(ledger.currentStreak(now: _at(17)), 1);
    });

    test('excusing that day closes the gap instead of restarting', () {
      // Wed the 16th — the sick day.
      expect(ledger.currentStreak(now: _at(17), calendar: _excusing([16])), 3);
    });

    test('an excused day pays nothing on its own', () {
      final excused = _excusing([16]);
      expect(ledger.totalPoints, 30);
      // Same events, same points — the calendar only changes how the run is
      // scored, never what is in the ledger.
      expect(ledger.currentStreak(now: _at(17), calendar: excused), 3);
      expect(ledger.totalPoints, 30);
      expect(ledger.countOf(RewardKind.visit), 0);
    });

    test('excusing does not invent a streak out of nothing', () {
      // Every school day of the week excused, but nothing was ever recorded.
      final calendar = _excusing([14, 15, 16, 17, 18]);
      expect(
        RewardLedger.empty.currentStreak(now: _at(18), calendar: calendar),
        0,
      );
    });

    test('best streak bridges excused days too', () {
      expect(ledger.bestStreak(calendar: _excusing([16])), 3);
      expect(ledger.bestStreak(), 2);
    });

    test('a check-in on an excused day joins the run rather than restarting',
        () {
      final calendar = _excusing([16]);
      expect(
        ledger.streakAfterActivityOn(_at(18), calendar: calendar),
        4,
      );
    });
  });

  group('daily check-in', () {
    test('pays a flat rate for the first two days, then escalates', () {
      expect(visitPoints(1), 3);
      expect(visitPoints(2), 3);
      expect(visitPoints(3), 5);
      expect(visitPoints(6), 5);
      expect(visitPoints(7), 8);
      expect(visitPoints(40), 8);
    });

    test('showing up never out-earns doing the work', () {
      expect(visitPoints(100), lessThan(RewardKind.turnedIn.points));
    });

    test('the day a check-in lands on continues an unbroken run', () {
      final ledger = _ledgerOf([
        _ev('v1', RewardKind.visit, on: 15),
        _ev('v2', RewardKind.visit, on: 14),
      ]);
      expect(ledger.streakAfterActivityOn(_at(16)), 3);
      expect(nextVisitPoints(ledger.currentStreak(now: _at(15))), 5);
    });

    test('a run that already lapsed restarts at day one', () {
      final ledger = _ledgerOf([
        _ev('v1', RewardKind.visit, on: 15),
        _ev('v2', RewardKind.visit, on: 14),
      ]);
      // Wed and Thu both came and went; Friday starts over.
      expect(ledger.streakAfterActivityOn(_at(18)), 1);
      expect(visitPoints(ledger.streakAfterActivityOn(_at(18))), 3);
    });

    test('a Monday check-in continues Friday’s run across the weekend', () {
      final ledger = _ledgerOf([
        _ev('v1', RewardKind.visit, on: 18), // Fri
        _ev('v2', RewardKind.visit, on: 17), // Thu
      ]);
      expect(ledger.streakAfterActivityOn(_at(21)), 3);
    });

    test('a day already active is not double-counted by the streak', () {
      final ledger = _ledgerOf([
        _ev('t1', RewardKind.turnedIn, on: 15),
        _ev('v1', RewardKind.visit, on: 14),
      ]);
      // Turning something in on Tuesday already put it on the board, so the
      // check-in joins day 2 rather than inventing a day 3.
      expect(ledger.streakAfterActivityOn(_at(15)), 2);
    });

    test('opening the app is what keeps a streak alive on an idle day', () {
      var ledger = _ledgerOf([_ev('t1', RewardKind.turnedIn, on: 14)]);
      expect(ledger.currentStreak(now: _at(14)), 1);
      // No assignments touched Tuesday — the visit alone carries the run.
      ledger = ledger.add(_ev('v1', RewardKind.visit, on: 15));
      expect(ledger.currentStreak(now: _at(15)), 2);
    });

    test('ten separate days earn the showing-up badge', () {
      final ledger = _ledgerOf([
        for (var i = 0; i < 10; i++)
          _ev('v$i', RewardKind.visit, on: 1 + i * 2),
      ]);
      // Deliberately non-consecutive: coming back at all is the thing being
      // rewarded here, separately from keeping a run alive.
      expect(ledger.earnedBadgeIds(now: _at(19)), contains('showed-up-10'));
    });
  });

  group('badges', () {
    test('a locked badge reports progress toward its target', () {
      final ledger = _ledgerOf([
        for (var i = 0; i < 3; i++)
          _ev('t$i', RewardKind.turnedIn, on: 14 + i),
      ]);
      final badge = ledger.badges().firstWhere((b) => b.id == 'turned-in-5');
      expect(badge.earned, isFalse);
      expect(badge.progress, 3);
      expect(badge.fraction, closeTo(0.6, 0.001));
    });

    test('emailing a teacher once earns the thumbs-up badge', () {
      final ledger = _ledgerOf([_ev('e', RewardKind.teacherEmail)]);
      expect(ledger.earnedBadgeIds(), contains('spoke-up-1'));
    });

    test('a streak badge stays earned after the streak lapses', () {
      final ledger = _ledgerOf([
        for (var i = 0; i < 3; i++)
          _ev('t$i', RewardKind.turnedIn, on: 14 + i),
      ]);
      expect(ledger.currentStreak(now: _at(30)), 0);
      expect(ledger.earnedBadgeIds(now: _at(30)), contains('streak-3'));
    });
  });

  group('applyReward', () {
    test('awards, and reports the running total and streak', () {
      final result = applyReward(
        RewardLedger.empty,
        _ev('x', RewardKind.turnedIn),
        now: _at(14),
      );
      expect(result, isNotNull);
      expect(result!.ledger.events, hasLength(1));
      expect(result.outcome.totalPoints, 10);
      expect(result.outcome.streak, 1);
      expect(result.outcome.event.points, 10);
    });

    test('a repeat of the same id is refused, so points cannot be farmed', () {
      final first =
          applyReward(RewardLedger.empty, _ev('x', RewardKind.turnedIn))!;
      final second = applyReward(first.ledger, _ev('x', RewardKind.turnedIn));
      expect(second, isNull);
    });

    test('the same assignment can pay once per kind', () {
      final planned = applyReward(
        RewardLedger.empty,
        _ev('planned:k1', RewardKind.planned),
      )!;
      final turnedIn = applyReward(
        planned.ledger,
        _ev('turnedIn:k1', RewardKind.turnedIn),
      );
      expect(turnedIn, isNotNull);
      expect(turnedIn!.outcome.totalPoints, 12);
    });

    test('crossing a badge threshold reports it exactly once', () {
      var ledger = RewardLedger.empty;
      final announced = <String>[];
      for (var i = 0; i < 6; i++) {
        final r = applyReward(
          ledger,
          _ev('t$i', RewardKind.turnedIn, on: 14 + i),
          now: _at(14 + i),
        )!;
        ledger = r.ledger;
        announced.addAll(r.outcome.newBadges.map((b) => b.id));
      }
      expect(announced.where((id) => id == 'turned-in-5'), hasLength(1));
      // The 5th turn-in is the one that crosses it.
      expect(announced.indexOf('turned-in-5'), greaterThan(0));
    });

    test('crossing a level threshold sets newLevel just once', () {
      var ledger = RewardLedger.empty;
      final levelUps = <String>[];
      for (var i = 0; i < 8; i++) {
        final r = applyReward(
          ledger,
          _ev('t$i', RewardKind.turnedIn, on: 14 + i),
          now: _at(14 + i),
        )!;
        ledger = r.ledger;
        final up = r.outcome.newLevel;
        if (up != null) levelUps.add(up.name);
      }
      expect(levelUps, ['Warming up']);
    });

    test('headlines rotate rather than repeating verbatim', () {
      var ledger = RewardLedger.empty;
      final headlines = <String>[];
      for (var i = 0; i < 3; i++) {
        final r = applyReward(ledger, _ev('t$i', RewardKind.turnedIn))!;
        ledger = r.ledger;
        headlines.add(r.outcome.headline);
      }
      expect(headlines.toSet(), hasLength(3));
    });

    test('a milestone award is flagged for the bigger celebration', () {
      final r = applyReward(RewardLedger.empty, _ev('x', RewardKind.turnedIn))!;
      // The very first event earns "First step".
      expect(r.outcome.isMilestone, isTrue);
      expect(r.outcome.newBadges.map((b) => b.id), contains('first-step'));
    });

    test('the calendar it is scored against reaches the outcome', () {
      final before = _ledgerOf([
        _ev('a', RewardKind.turnedIn, on: 15),
        _ev('b', RewardKind.turnedIn, on: 14),
      ]);
      final excused = applyReward(
        before,
        _ev('c', RewardKind.turnedIn, on: 17),
        now: _at(17),
        calendar: _excusing([16]),
      )!;
      final notExcused = applyReward(
        before,
        _ev('c', RewardKind.turnedIn, on: 17),
        now: _at(17),
      )!;
      expect(excused.outcome.streak, 3);
      expect(notExcused.outcome.streak, 1);
    });
  });

  group('json round trip', () {
    test('preserves events and sorts them oldest first', () {
      final original = _ledgerOf([
        _ev('b', RewardKind.turnedIn, on: 16, label: 'Newer'),
        _ev('a', RewardKind.planned, on: 14, label: 'Older'),
      ]);
      final restored = RewardLedger.fromJson(original.toJson());
      expect(restored.events.map((e) => e.label), ['Older', 'Newer']);
      expect(restored.totalPoints, original.totalPoints);
      expect(restored.events.first.kind, RewardKind.planned);
    });

    test('drops entries this build cannot read instead of throwing', () {
      final restored = RewardLedger.fromJson({
        'events': [
          {'id': 'ok', 'kind': 'turnedIn', 'points': 10, 'at': '2026-05-01T12:00:00Z', 'label': 'Fine'},
          {'id': 'future', 'kind': 'teleported', 'points': 99, 'at': '2026-05-02T12:00:00Z'},
          {'id': 'broken', 'kind': 'turnedIn', 'at': 'not-a-date'},
          'not even a map',
        ],
      });
      expect(restored.events, hasLength(1));
      expect(restored.totalPoints, 10);
    });

    test('a missing file reads as an empty ledger', () {
      expect(RewardLedger.fromJson(null).isEmpty, isTrue);
      expect(RewardLedger.fromJson(const {}).totalPoints, 0);
    });
  });
}

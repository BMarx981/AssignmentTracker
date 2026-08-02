// The rewards screen is a pure read of the ledger, so these check that each
// derived number reaches the right place on screen — and that the empty
// ledger gets the "here's what earns points" state instead of a blank page.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:assignment_tracker_app/domain/rewards.dart';
import 'package:assignment_tracker_app/domain/streak_calendar.dart';
import 'package:assignment_tracker_app/screens/rewards_screen.dart';
import 'package:assignment_tracker_app/state/rewards_providers.dart';
import 'package:assignment_tracker_app/theme/app_theme.dart';

RewardEvent _event(
  String id,
  RewardKind kind, {
  int dayOffset = 0,
  String label = 'Chapter 8 Questions',
}) {
  final now = DateTime.now();
  return RewardEvent(
    id: id,
    kind: kind,
    points: kind.points,
    at: DateTime(now.year, now.month, now.day + dayOffset, 12).toUtc(),
    label: label,
  );
}

Future<void> pumpScreen(
  WidgetTester tester,
  RewardLedger ledger, {
  StreakCalendar calendar = const StreakCalendar(restDays: {}),
}) async {
  // Tall enough that the level card, badge grid, and activity feed are all
  // laid out at once — these assertions are about what the screen contains,
  // not about what fits in a phone viewport.
  tester.view.physicalSize = const Size(500, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentRewardsProvider.overrideWithValue(
          // The default has no rest days: real weekends would make these
          // assertions depend on the weekday the suite runs on. StreakCalendar's
          // own rules are covered in the domain tests; tests that care about
          // the weekend copy pass their own.
          AsyncData(RewardsView(ledger: ledger, calendar: calendar)),
        ),
      ],
      child: MaterialApp(
        theme: buildDarkTheme(),
        home: const RewardsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an empty ledger explains what earns points', (tester) async {
    await pumpScreen(tester, RewardLedger.empty);

    expect(find.text('No points yet'), findsOneWidget);
    // One chip per kind, each naming its payout.
    expect(find.text('✅ Turned in +10'), findsOneWidget);
    expect(find.text('👍 Emailed about +15'), findsOneWidget);
  });

  testWidgets('the level card shows rank, total, and the gap to the next',
      (tester) async {
    await pumpScreen(
      tester,
      RewardLedger([
        for (var i = 0; i < 6; i++)
          _event('t$i', RewardKind.turnedIn, dayOffset: -i),
      ]),
    );

    expect(find.text('Warming up'), findsOneWidget);
    expect(find.text('60'), findsOneWidget);
    expect(find.text('90 more to 🚀 On a roll'), findsOneWidget);
  });

  testWidgets('the check-in strip prices tomorrow off the current run',
      (tester) async {
    await pumpScreen(
      tester,
      RewardLedger([
        for (var i = 0; i < 2; i++)
          _event('v$i', RewardKind.visit, dayOffset: -i),
      ]),
    );

    // Two days in, so tomorrow is day 3 — where the rate first steps up.
    expect(find.text('Day 2. Come back tomorrow for +5.'), findsOneWidget);
    expect(
      find.text('Check-ins are worth more the longer the run goes.'),
      findsOneWidget,
    );
  });

  testWidgets('at the ceiling the strip names what a missed day costs',
      (tester) async {
    await pumpScreen(
      tester,
      RewardLedger([
        for (var i = 0; i < 8; i++)
          _event('v$i', RewardKind.visit, dayOffset: -i),
      ]),
    );

    expect(find.text('Day 8. Come back tomorrow for +8.'), findsOneWidget);
    expect(
      find.text('Miss a school day and the check-in drops back to +3.'),
      findsOneWidget,
    );
  });

  testWidgets('going into a weekend, the strip says the run is safe',
      (tester) async {
    await pumpScreen(
      tester,
      RewardLedger([
        for (var i = 0; i < 3; i++)
          _event('v$i', RewardKind.visit, dayOffset: -i),
      ]),
      // Whatever tomorrow happens to be, treat it as a rest day.
      calendar: StreakCalendar(
        restDays: {DateTime.now().add(const Duration(days: 1)).weekday},
      ),
    );

    expect(
      find.text("It's the weekend — your run is safe either way, but "
          'checking in still pays.'),
      findsOneWidget,
    );
    // The offer still stands; a weekend check-in pays like any other.
    expect(find.textContaining('Come back tomorrow for +'), findsOneWidget);
  });

  testWidgets('a check-in reads as one line in the activity feed',
      (tester) async {
    await pumpScreen(
      tester,
      RewardLedger([
        RewardEvent(
          id: 'visit:today',
          kind: RewardKind.visit,
          points: 8,
          at: DateTime.now().toUtc(),
          label: 'Day 7 check-in',
        ),
      ]),
    );

    expect(find.text('Day 7 check-in'), findsOneWidget);
    expect(find.textContaining('Checked in · '), findsOneWidget);
    expect(find.text('+8'), findsOneWidget);
  });

  testWidgets('the stat row counts the streak, turn-ins, and teachers asked',
      (tester) async {
    await pumpScreen(
      tester,
      RewardLedger([
        _event('a', RewardKind.turnedIn, dayOffset: 0),
        _event('b', RewardKind.turnedIn, dayOffset: -1),
        _event('c', RewardKind.teacherEmail, dayOffset: -2, label: 'Science 6'),
      ]),
    );

    expect(find.text('day streak'), findsOneWidget);
    expect(find.text('3'), findsWidgets); // 3-day streak
    expect(find.text('turned in'), findsOneWidget);
    expect(find.text('teachers asked'), findsOneWidget);
  });

  testWidgets('locked badges show their progress, earned ones do not',
      (tester) async {
    await pumpScreen(
      tester,
      RewardLedger([
        for (var i = 0; i < 3; i++)
          _event('t$i', RewardKind.turnedIn, dayOffset: -i),
      ]),
    );

    // 3 of the 5 needed for "Five down".
    expect(find.text('Five down'), findsOneWidget);
    expect(find.text('3 / 5'), findsOneWidget);
    // "First step" is already earned, so it carries no counter.
    expect(find.text('First step'), findsOneWidget);
    expect(find.text('1 / 1'), findsNothing);
  });

  testWidgets('the activity feed lists newest first', (tester) async {
    await pumpScreen(
      tester,
      RewardLedger([
        _event('a', RewardKind.planned, dayOffset: -3, label: 'Older thing'),
        _event('b', RewardKind.turnedIn, dayOffset: 0, label: 'Newer thing'),
      ]),
    );

    final newer = tester.getTopLeft(find.text('Newer thing')).dy;
    final older = tester.getTopLeft(find.text('Older thing')).dy;
    expect(newer, lessThan(older));
    expect(find.textContaining('Turned in · '), findsOneWidget);
    // Elapsed time is floored, so a noon stamp three days back reads as 2 or 3
    // depending on the hour the suite runs at.
    expect(find.textContaining('days ago'), findsOneWidget);
  });
}

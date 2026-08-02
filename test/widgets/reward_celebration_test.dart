// The overlay's own contract: it plays whatever lands in the feed, gets out
// of the way on its own, and never eats a tap on the way past.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:assignment_tracker_app/domain/rewards.dart';
import 'package:assignment_tracker_app/state/rewards_providers.dart';
import 'package:assignment_tracker_app/theme/app_theme.dart';
import 'package:assignment_tracker_app/widgets/reward_celebration.dart';

RewardOutcome _outcome({
  RewardKind kind = RewardKind.turnedIn,
  String headline = 'Turned in. Nice work.',
  int totalPoints = 40,
  int streak = 1,
  List<RewardBadge> newBadges = const [],
  RewardLevel? newLevel,
}) =>
    RewardOutcome(
      event: RewardEvent(
        id: 'turnedIn:k1',
        kind: kind,
        points: kind.points,
        at: DateTime.utc(2026, 5, 1, 12),
        label: 'Chapter 8 Questions',
      ),
      headline: headline,
      totalPoints: totalPoints,
      streak: streak,
      newBadges: newBadges,
      newLevel: newLevel,
    );

void main() {
  late ProviderContainer container;

  Future<void> pumpHost(WidgetTester tester, {VoidCallback? onTapBelow}) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildDarkTheme(),
          home: RewardHost(
            child: Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: onTapBelow ?? () {},
                  child: const Text('Underneath'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(RewardHost)),
    );
  }

  testWidgets('an award in the feed plays, then clears itself', (tester) async {
    await pumpHost(tester);
    expect(find.textContaining('Nice work'), findsNothing);

    container.read(rewardFeedProvider.notifier).push(_outcome());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Turned in. Nice work.'), findsOneWidget);
    expect(find.text('+10'), findsOneWidget);
    expect(find.text('40 points total'), findsOneWidget);

    await tester.pumpAndSettle();

    // Gone from the screen AND drained from the feed, so navigating to another
    // screen can't replay it.
    expect(find.text('Turned in. Nice work.'), findsNothing);
    expect(container.read(rewardFeedProvider), isNull);
  });

  testWidgets('a streak takes over the subtitle', (tester) async {
    await pumpHost(tester);
    container.read(rewardFeedProvider.notifier).push(_outcome(streak: 4));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('🔥 4-day streak · 40 pts'), findsOneWidget);
    expect(find.text('40 points total'), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('a new badge outranks the plain headline', (tester) async {
    await pumpHost(tester);
    container.read(rewardFeedProvider.notifier).push(_outcome(
          kind: RewardKind.teacherEmail,
          newBadges: const [
            RewardBadge(
              id: 'spoke-up-1',
              emoji: '👍',
              name: 'Spoke up',
              description: 'Email a teacher about an assignment.',
              progress: 1,
              target: 1,
            ),
          ],
        ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Badge unlocked: Spoke up'), findsOneWidget);
    expect(find.text('+15'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('a level-up outranks a badge', (tester) async {
    await pumpHost(tester);
    container.read(rewardFeedProvider.notifier).push(_outcome(
          newLevel: kRewardLevels[2],
          newBadges: const [
            RewardBadge(
              id: 'turned-in-5',
              emoji: '✅',
              name: 'Five down',
              description: 'Turn in 5 assignments.',
              progress: 5,
              target: 5,
            ),
          ],
        ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Level up — On a roll!'), findsOneWidget);
    expect(find.text('Badge unlocked: Five down'), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('a second award mid-animation replaces the first', (tester) async {
    await pumpHost(tester);
    container.read(rewardFeedProvider.notifier).push(_outcome());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Turned in. Nice work.'), findsOneWidget);

    container
        .read(rewardFeedProvider.notifier)
        .push(_outcome(headline: 'One less thing.', totalPoints: 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Turned in. Nice work.'), findsNothing);
    expect(find.text('One less thing.'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('One less thing.'), findsNothing);
    expect(container.read(rewardFeedProvider), isNull);
  });

  testWidgets('the toast never swallows a tap meant for the screen',
      (tester) async {
    var taps = 0;
    await pumpHost(tester, onTapBelow: () => taps++);
    container.read(rewardFeedProvider.notifier).push(_outcome());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Underneath'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });
}

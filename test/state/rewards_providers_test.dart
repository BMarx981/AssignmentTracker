// The daily check-in's real contract: it fires once per calendar day no
// matter how often it's called, it survives a restart because it went to
// disk, and its payout climbs with the run.
//
// path_provider has no implementation under `flutter test`, so the platform
// interface is stubbed to hand back a temp directory.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:assignment_tracker_app/domain/rewards.dart';
import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:assignment_tracker_app/state/excused_days_providers.dart';
import 'package:assignment_tracker_app/state/rewards_providers.dart';
import 'package:assignment_tracker_app/state/student_providers.dart';
import 'package:assignment_tracker_app/storage/local_store.dart';

class _TempPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TempPathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

DateTime _day(int offset) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + offset, 9);
}

void main() {
  late Directory tempDir;
  late LocalStore store;

  const student = Student(studentId: 's1', name: 'Test Student');

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        selectedStudentProvider.overrideWithValue(const AsyncData(student)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('rewards_providers_test');
    PathProviderPlatform.instance = _TempPathProvider(tempDir.path);
    store = await LocalStore.instance();
  });

  setUp(() async {
    await store.writeRewards('s1', const {'events': <Object>[]});
    await store.writeExcusedDays('s1', const {'days': <Object>[]});
  });

  /// A school-day offset from today, so these never accidentally land on a
  /// weekend and get skipped by the calendar.
  DateTime schoolDay(int back) {
    var cursor = DateTime.now();
    var remaining = back;
    while (true) {
      final isRest = cursor.weekday == DateTime.saturday ||
          cursor.weekday == DateTime.sunday;
      if (!isRest) {
        if (remaining == 0) {
          return DateTime(cursor.year, cursor.month, cursor.day, 9);
        }
        remaining--;
      }
      cursor = cursor.subtract(const Duration(days: 1));
    }
  }

  tearDownAll(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('the first open of the day pays and the rest of the day does not',
      () async {
    final container = makeContainer();
    final service = container.read(rewardServiceProvider);

    final first = await service.recordVisit();
    expect(first, isNotNull);
    expect(first!.event.kind, RewardKind.visit);
    expect(first.event.points, 3);
    // The first check-in a student ever sees must not greet them as a return
    // visitor.
    expect(first.headline, 'Good to see you.');
    expect(container.read(rewardFeedProvider), same(first));

    // Every later launch, resume, and navigation on the same day.
    expect(await service.recordVisit(), isNull);
    expect(await service.recordVisit(), isNull);
    expect(container.read(rewardsProvider('s1')).value!.events, hasLength(1));
  });

  test('simultaneous launch and resume still celebrate once', () async {
    final container = makeContainer();
    final service = container.read(rewardServiceProvider);

    final results = await Future.wait([
      service.recordVisit(),
      service.recordVisit(),
      service.recordVisit(),
    ]);

    // All three callers ride the one in-flight award, so they get back the
    // same outcome rather than three separate ones — one event on the ledger,
    // one value in the feed, one toast.
    expect(results[0], isNotNull);
    expect(results[1], same(results[0]));
    expect(results[2], same(results[0]));
    expect(container.read(rewardsProvider('s1')).value!.events, hasLength(1));
    expect(container.read(rewardFeedProvider), same(results[0]));
  });

  test('the check-in is on disk, so a restart does not pay twice', () async {
    final first = makeContainer();
    await first.read(rewardServiceProvider).recordVisit();

    final saved = RewardLedger.fromJson(await store.readRewards('s1'));
    expect(saved.events, hasLength(1));
    expect(saved.countOf(RewardKind.visit), 1);

    // A fresh container reads the ledger back off disk, as a cold launch would.
    final restarted = makeContainer();
    expect(await restarted.read(rewardServiceProvider).recordVisit(), isNull);
  });

  test('the payout climbs as the run builds and resets when it breaks',
      () async {
    final container = makeContainer();
    final notifier = container.read(rewardsProvider('s1').notifier);

    final paid = <int>[];
    for (var day = -6; day <= 0; day++) {
      final outcome = await notifier.recordVisit(now: _day(day));
      paid.add(outcome!.event.points);
    }
    expect(paid, [3, 3, 5, 5, 5, 5, 8]);
    expect(container.read(rewardsProvider('s1')).value!.currentStreak(), 7);

    // Skip a day, come back: the rate falls all the way back to the base.
    final afterGap = await notifier.recordVisit(now: _day(2));
    expect(afterGap!.event.points, 3);
    expect(afterGap.event.label, 'Day 1 check-in');
  });

  test('an assignment action already logged today folds into the same day',
      () async {
    final container = makeContainer();
    final notifier = container.read(rewardsProvider('s1').notifier);

    await notifier.recordVisit(now: _day(-1));
    await notifier.award(
      kind: RewardKind.turnedIn,
      id: 'turnedIn:k1',
      label: 'Chapter 8',
      at: _day(0),
    );

    // Today is already on the board, so the check-in continues the run at
    // day 2 rather than inventing a third day.
    final outcome = await notifier.recordVisit(now: _day(0));
    expect(outcome!.event.label, 'Day 2 check-in');
    expect(outcome.event.points, 3);
  });

  test('a sick day rescues the run instead of resetting it', () async {
    final container = makeContainer();
    final notifier = container.read(rewardsProvider('s1').notifier);

    // Two school days of showing up, then one missed, then back today.
    await notifier.recordVisit(now: schoolDay(3));
    await notifier.recordVisit(now: schoolDay(2));
    final beforeExcuse = await notifier.recordVisit(now: schoolDay(0));

    // The missed school day broke it, so today reads as a fresh day one.
    expect(beforeExcuse!.event.label, 'Day 1 check-in');
    expect(beforeExcuse.event.points, 3);
    expect(container.read(currentRewardsProvider).value!.streak, 1);

    // The parent excuses the day he was home sick.
    await container
        .read(excusedDaysProvider('s1').notifier)
        .excuse(schoolDay(1), reason: 'Sick');

    final view = container.read(currentRewardsProvider).value!;
    // The run reconnects across the gap: 1 becomes 3, the three days he
    // actually showed up. The sick day is skipped, not counted — being out
    // sick is not itself a day of showing up.
    expect(view.streak, 3);
    // And it paid nothing: same three check-ins, same nine points.
    expect(view.ledger.countOf(RewardKind.visit), 3);
    expect(view.ledger.totalPoints, 9);
  });

  test('the day after a sick day is priced off the rescued run', () async {
    final container = makeContainer();
    final notifier = container.read(rewardsProvider('s1').notifier);

    await notifier.recordVisit(now: schoolDay(3));
    await notifier.recordVisit(now: schoolDay(2));
    await container
        .read(excusedDaysProvider('s1').notifier)
        .excuse(schoolDay(1), reason: 'Sick');

    // Day 3 of a run that survived, so it pays the escalated rate rather than
    // starting over at +3.
    final outcome = await notifier.recordVisit(now: schoolDay(0));
    expect(outcome!.event.label, 'Day 3 check-in');
    expect(outcome.event.points, 5);
  });

  test('excused days persist and reload', () async {
    final first = makeContainer();
    await first
        .read(excusedDaysProvider('s1').notifier)
        .excuse(schoolDay(1), reason: 'Dentist');

    final restarted = makeContainer();
    final days =
        await restarted.read(excusedDaysProvider('s1').future);
    expect(days, hasLength(1));
    expect(days.first.reason, 'Dentist');

    await restarted
        .read(excusedDaysProvider('s1').notifier)
        .unexcuse(days.first.date);
    expect(restarted.read(excusedDaysProvider('s1')).value, isEmpty);
  });

  test('excusing the same day twice does not duplicate it', () async {
    final container = makeContainer();
    final notifier = container.read(excusedDaysProvider('s1').notifier);
    await notifier.excuse(schoolDay(1), reason: 'Sick');
    await notifier.excuse(schoolDay(1), reason: 'Sick again');
    expect(container.read(excusedDaysProvider('s1')).value, hasLength(1));
  });

  test('no selected student means nothing is awarded or announced', () async {
    final container = ProviderContainer(
      overrides: [
        selectedStudentProvider.overrideWithValue(const AsyncData(null)),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(rewardServiceProvider).recordVisit(), isNull);
    expect(container.read(rewardFeedProvider), isNull);
  });
}

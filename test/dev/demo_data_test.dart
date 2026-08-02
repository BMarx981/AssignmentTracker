// Verifies the demo seed actually produces something worth looking at:
// it round-trips through LocalStore + DataAssembler (the real read path), the
// dates land inside the dashboard's default window, the seeded local statuses
// and comments attach to the assignments they name, and every row labelled
// "[Canvas twin …]" / "[Canvas only …]" merges the way its label claims.
//
// path_provider has no implementation under `flutter test`, so the platform
// interface is stubbed to hand back a temp directory.

import 'dart:io';

import 'package:assignment_tracker_app/dev/demo_data.dart';
import 'package:assignment_tracker_app/dev/demo_seed.dart';
import 'package:assignment_tracker_app/domain/assignment_situation.dart';
import 'package:assignment_tracker_app/domain/data_assembler.dart';
import 'package:assignment_tracker_app/domain/merged.dart';
import 'package:assignment_tracker_app/domain/priority.dart';
import 'package:assignment_tracker_app/domain/rewards.dart';
import 'package:assignment_tracker_app/domain/streak_calendar.dart';
import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:assignment_tracker_app/storage/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The streak calendar a seeded student is meant to be scored against.
StreakCalendar _calendarOf(DemoStudent student, DateTime anchor) {
  final days = (student.excusedDays(anchor)['days'] as List)
      .map((d) => (d as Map)['date'] as String)
      .toSet();
  return StreakCalendar(excusedDays: days);
}

class _TempPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TempPathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  late Directory tempDir;
  late LocalStore store;
  late DataPayload payload;

  Student studentNamed(String name) =>
      payload.students.firstWhere((s) => s.name == name);

  List<MergedCourse> mergedFor(String name) {
    final s = studentNamed(name);
    return mergeData(s.canvas, s.synergy);
  }

  DateRange defaultRange() {
    final today = DateTime.now();
    return DateRange(
      start: DateTime(today.year, today.month - 1, today.day),
      end: DateTime(today.year, today.month + 1, today.day),
    );
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('demo_data_test');
    PathProviderPlatform.instance = _TempPathProvider(tempDir.path);
    store = await LocalStore.instance();
    await seedDemoData(store);
    payload = await DataAssembler(store).assemble();
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('seeds four students spanning both sources and each on its own', () {
    expect(payload.students.map((s) => s.name), ['Milo', 'Nora', 'Otis', 'Pearl']);

    final milo = studentNamed('Milo');
    expect(milo.synergy!.courses, hasLength(6));
    expect(milo.canvas!.courses, hasLength(2));

    // Otis is Canvas-only, Pearl is Synergy-only.
    expect(studentNamed('Otis').synergy?.courses ?? const [], isEmpty);
    expect(studentNamed('Otis').canvas!.courses, isNotEmpty);
    expect(studentNamed('Pearl').canvas?.courses ?? const [], isEmpty);
    expect(studentNamed('Pearl').synergy!.courses, isNotEmpty);
  });

  test('every Canvas row merges exactly the way its label says', () {
    for (final name in ['Milo', 'Nora']) {
      final student = studentNamed(name);
      final merged = mergeData(student.canvas, student.synergy);
      final byCanvasId = {
        for (final c in merged)
          for (final i in c.items)
            if (i.canvasId != null) i.canvasId!: i,
      };
      // The Yearbook course has no Synergy counterpart and is dropped whole,
      // so its rows are expected to be absent regardless of their label.
      final droppedCourseIds = {'30705'};

      for (final cc in student.canvas!.courses) {
        final courseId = cc.raw['id'].toString();
        for (final a in cc.assignments) {
          final id = a.raw['id'].toString();
          final item = byCanvasId[id];
          if (droppedCourseIds.contains(courseId)) {
            expect(item, isNull, reason: '${a.name} should have been dropped');
            continue;
          }
          if (a.name.contains('[Canvas twin')) {
            expect(item?.source, 'both', reason: '${a.name} should merge');
          } else if (a.name.contains('excused')) {
            expect(item, isNull, reason: '${a.name} should be dropped');
          } else if (a.name.contains('[Canvas only')) {
            expect(item?.source, 'canvas',
                reason: '${a.name} should stay Canvas-only');
          }
        }
      }
    }
  });

  test('seeded dates are in range except the two labelled exceptions', () {
    final range = defaultRange();
    for (final s in payload.students) {
      for (final c in mergeData(s.canvas, s.synergy)) {
        for (final i in c.items) {
          final expected = !i.name.contains('outside the date range') &&
              !i.name.contains('no due date');
          expect(
            range.contains(i.date),
            expected,
            reason: '${c.name} / ${i.name} at ${i.date}',
          );
        }
      }
    }
  });

  test('Milo covers every merged-item status flag', () {
    final flags = {
      for (final c in mergedFor('Milo'))
        for (final i in c.items) i.status,
    };
    expect(
      flags,
      containsAll([
        'missing',
        'zero_graded',
        'half_credit_missing',
        'not_graded',
        'graded',
        'unknown',
        'submitted_pending',
        'other',
      ]),
    );
    // ...and both non-Synergy source values.
    final sources = {
      for (final c in mergedFor('Milo'))
        for (final i in c.items) i.source,
    };
    expect(sources, containsAll(['synergy', 'canvas', 'both']));
  });

  test('the catch-up list is non-empty and led by the failing course', () {
    final student = studentNamed('Milo');
    final today = DateTime.now();
    final range = defaultRange();
    final ranked = <(String, String, double)>[];
    for (final c in mergeData(student.canvas, student.synergy)) {
      for (final i in c.items) {
        final score = priorityScore(
          item: i,
          course: c,
          today: today,
          thresholds: student.scoreThresholds,
          statusByKey: student.assignmentStatus,
          range: range,
        );
        if (score >= 0) ranked.add((c.name, i.name, score));
      }
    }
    ranked.sort((a, b) => b.$3.compareTo(a.$3));

    expect(ranked.length, greaterThan(10));
    // Language Arts is at 57% — the most distressed course, so it should own
    // the top slot ahead of Math at 63.5%.
    expect(ranked.first.$1, 'Language Arts 6');
    // PE is at 100% with nothing missing; it should contribute nothing.
    expect(ranked.any((r) => r.$1 == 'PE 6'), isFalse);
  });

  test('course-level grade routes each have a representative', () {
    final milo = mergedFor('Milo');
    // Half-credit policy recomputes the percent the card shows.
    final history = milo.firstWhere((c) => c.name == 'Historical Inquiry 6');
    expect(history.policyHalfCredit, isTrue);
    expect(history.synergyAltHalfCreditPercent, isNotNull);
    // Computed-percent-only course.
    final science = milo.firstWhere((c) => c.name == 'Science 6');
    expect(science.synergyPercentIsComputed, isTrue);
    // No teacher at all.
    expect(
      milo.firstWhere((c) => c.name == 'Study Skills 6').teacher,
      isNull,
    );
    // Teacher with no email.
    expect(science.teacher, isNotNull);
    expect(science.teacherEmail, isNull);

    // Canvas worst-case grading, no Synergy percent anywhere.
    final otis = mergedFor('Otis');
    expect(otis.map((c) => c.name), contains('World Geography 7'));
    for (final c in otis) {
      expect(c.synergyPercent, isNull);
      expect(c.canvasAvgWithMissing, isNotNull);
    }
    // A Canvas course with no assignments is dropped.
    expect(otis.any((c) => c.name.startsWith('Band')), isFalse);

    // No grade at all → courseDistress falls back to its flat 50.
    final choir = mergedFor('Pearl').firstWhere((c) => c.name == 'Choir 8');
    expect(choir.synergyPercent, isNull);
    expect(choir.canvasAvgWithMissing, isNull);
    expect(courseDistress(choir), 50);
    // A course with no assignments still gets a card.
    expect(
      mergedFor('Pearl').firstWhere((c) => c.name == 'Study Hall 8').items,
      isEmpty,
    );
  });

  test('the score threshold pulls a low graded item into the list', () {
    final student = studentNamed('Milo');
    expect(student.scoreThresholds['Language Arts 6'], 70);
    final la =
        mergedFor('Milo').firstWhere((c) => c.name == 'Language Arts 6');
    // The vocab quiz is Canvas-only and scored 12/20 = 60%, under the 70%
    // threshold. Synergy-sourced graded rows flatten to 'ok' and are never
    // actionable, so the Canvas-only path is the one the threshold governs.
    final quiz = la.items.firstWhere((i) => i.name.startsWith('Greek Roots'));
    expect(quiz.status, 'graded');
    expect(isActionable(quiz, la.name, student.scoreThresholds), isTrue);
    expect(isActionable(quiz, la.name, const {}), isFalse);

    // ...and its sibling at 90% stays out of it.
    final over = la.items.firstWhere((i) => i.name.startsWith('Prefix'));
    expect(isActionable(over, la.name, student.scoreThresholds), isFalse);
  });

  test('seeded local statuses attach to real assignments', () {
    for (final student in payload.students) {
      final byKey = {
        for (final c in mergeData(student.canvas, student.synergy))
          for (final i in c.items) i.key: i,
      };
      for (final entry in student.assignmentStatus.entries) {
        expect(
          byKey.containsKey(entry.key),
          isTrue,
          reason: '${student.name}: orphaned status for '
              '${entry.value.assignmentName}',
        );
      }
    }

    final milo = studentNamed('Milo');
    final byKey = {
      for (final c in mergedFor('Milo'))
        for (final i in c.items) i.key: i,
    };
    // The status seeded onto the already-graded Essay 2 must be suppressed.
    final essay =
        byKey.values.firstWhere((i) => i.name.startsWith('Character Analysis'));
    expect(getLocalStatus(essay, milo.assignmentStatus), isNull);

    // ...while the one on a still-missing item shows through.
    final planned = byKey.values
        .firstWhere((i) => i.name.startsWith('Fraction Decimal'));
    expect(getLocalStatus(planned, milo.assignmentStatus)?.status, 'planned');

    // All four claim shapes the sign-off PDF branches on are present.
    final claims = milo.assignmentStatus.values;
    expect(claims.any((e) => e.status == 'planned' && e.plannedDate != null),
        isTrue);
    expect(claims.any((e) => e.status == 'planned' && e.plannedDate == null),
        isTrue);
    expect(claims.any((e) => e.status == 'complete_pending_submission'), isTrue);
    expect(
      claims.any((e) =>
          e.status == 'submitted_pending_feedback' && e.submittedDate != null),
      isTrue,
    );
    expect(
      claims.any((e) =>
          e.status == 'submitted_pending_feedback' && e.submittedDate == null),
      isTrue,
    );
  });

  test('seeded comments attach to real assignments', () {
    for (final student in payload.students) {
      final keys = {
        for (final c in mergeData(student.canvas, student.synergy))
          for (final i in c.items) i.key,
      };
      expect(student.comments, isNotEmpty, reason: student.name);
      for (final key in student.comments.keys) {
        expect(keys.contains(key), isTrue,
            reason: '${student.name}: orphaned comment on $key');
      }
    }

    // One thread carries replies — the deep path in the comments panel.
    final milo = studentNamed('Milo');
    expect(
      milo.comments.values.any((threads) =>
          threads.any((t) => t.replies.length >= 2)),
      isTrue,
    );
  });

  test('Milo seeds every AssignmentState the action sheet can open on', () {
    final milo = studentNamed('Milo');
    final states = <AssignmentState>{};
    for (final c in mergedFor('Milo')) {
      for (final i in c.items) {
        final state = resolveSituation(
          item: i,
          statusByKey: milo.assignmentStatus,
          comments: milo.comments,
        ).state;
        if (state != null) states.add(state);
      }
    }
    expect(states, AssignmentState.values.toSet());
  });

  test('the teacher check-in list covers each of its email fallbacks', () {
    final milo = studentNamed('Milo');
    final flagged = <String, List<MergedItem>>{};
    for (final c in mergedFor('Milo')) {
      final items = c.items
          .where((i) => hasNote(milo.comments[i.key] ?? const [], kTeacherCheckInNote))
          .toList();
      if (items.isNotEmpty) flagged[c.name] = items;
    }

    // One course with two flagged items → "Email teacher about all 2".
    expect(flagged['Historical Inquiry 6'], hasLength(2));
    // A teacher with an address, one with a name but no address, and a course
    // with no teacher at all.
    final courses = {for (final c in mergedFor('Milo')) c.name: c};
    expect(courses['Historical Inquiry 6']!.teacherEmail, isNotNull);
    expect(flagged.containsKey('Science 6'), isTrue);
    expect(courses['Science 6']!.teacher, isNotNull);
    expect(courses['Science 6']!.teacherEmail, isNull);
    expect(flagged.containsKey('Study Skills 6'), isTrue);
    expect(courses['Study Skills 6']!.teacher, isNull);

    // One marker carries a reply, so unflagging it is a deliberate no-op.
    final withReply = flagged.values
        .expand((items) => items)
        .expand((i) => milo.comments[i.key] ?? const <CommentThread>[])
        .where((t) => t.text == kTeacherCheckInNote && t.replies.isNotEmpty);
    expect(withReply, isNotEmpty);

    // Every student has at least one, so the dashboard badge is always visible.
    for (final s in payload.students) {
      final any = mergeData(s.canvas, s.synergy).any((c) => c.items.any(
          (i) => hasNote(s.comments[i.key] ?? const [], kTeacherCheckInNote)));
      expect(any, isTrue, reason: '${s.name} has no teacher check-in flag');
    }
  });

  test('planned dates cover all three sheet presets plus a custom date', () {
    final today = DateTime.now();
    String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final weekend = today.weekday == DateTime.saturday ||
            today.weekday == DateTime.sunday
        ? today
        : today.add(Duration(days: DateTime.saturday - today.weekday));
    final presets = {
      ymd(today),
      ymd(today.add(const Duration(days: 1))),
      ymd(weekend),
    };

    final planned = [
      for (final s in payload.students)
        for (final e in s.assignmentStatus.values)
          if (e.status == 'planned') e.plannedDate,
    ];
    expect(planned, containsAll(presets));
    // ...and one that matches none of them, plus one with no date at all.
    expect(planned.any((d) => d != null && !presets.contains(d)), isTrue);
    expect(planned.any((d) => d == null), isTrue);
  });

  test('demoFiles writes one file per student plus the shared three', () {
    final files = demoFiles(DateTime.now());
    expect(files.keys, contains('canvas_data.json'));
    expect(files.keys, contains('synergy_data.json'));
    expect(files.keys, contains('grade_bands.json'));
    expect(files.length, 3 + demoStudents.length * 5);
  });

  test('the seeded reward ledgers cover the rewards screen top to bottom', () {
    final now = DateTime.now();
    final ledgers = <String, RewardLedger>{
      for (final s in demoStudents)
        s.name: RewardLedger.fromJson(s.rewards(now)),
    };
    final calendars = <String, StreakCalendar>{
      for (final s in demoStudents) s.name: _calendarOf(s, now),
    };

    // Milo carries the fleshed-out one: mid-level, a live check-in run at the
    // escalated rate, and a badge case with both earned and locked tiles.
    final milo = ledgers['Milo']!;
    expect(milo.totalPoints, 179);
    expect(milo.level.name, 'On a roll');
    expect(milo.nextLevel?.name, 'Locked in');
    expect(milo.currentStreak(calendar: calendars['Milo']), 7);
    final earned = milo.earnedBadgeIds(calendar: calendars['Milo']);
    expect(
      earned,
      containsAll(['first-step', 'turned-in-5', 'spoke-up-1', 'streak-3', 'streak-7']),
    );
    expect(
      milo.badges(calendar: calendars['Milo'])
          .any((b) => !b.earned && b.progress > 0),
      isTrue,
    );

    // Nora is early days; Pearl's run lapsed and restarted, which is the
    // state the "come back tomorrow" strip exists for; Otis has nothing,
    // so the empty state sits on a real profile.
    final nora = ledgers['Nora']!;
    expect(nora.totalPoints, 23);
    expect(nora.currentStreak(calendar: calendars['Nora']), 2);

    final pearl = ledgers['Pearl']!;
    expect(pearl.earnedBadgeIds(), contains('spoke-up-1'));
    expect(pearl.currentStreak(calendar: calendars['Pearl']), 1);
    expect(pearl.bestStreak(calendar: calendars['Pearl']), 2);

    expect(ledgers['Otis']!.isEmpty, isTrue);

    // Milo is the one with a sick day on file, so the parent controls screen
    // has a real row to show and not just its empty state.
    expect(calendars['Milo']!.excusedDays, hasLength(1));
    expect(calendars['Nora']!.excusedDays, isEmpty);
  });

  test('the seeded runs land on school days, so they read the same any day',
      () {
    DemoStudent demo(String name) =>
        demoStudents.firstWhere((s) => s.name == name);
    // Seeding on a Monday and on a Friday has to produce the same streak, or
    // the demo tells a different story depending on when it was set up.
    for (final anchor in [
      DateTime(2026, 9, 14), // Mon
      DateTime(2026, 9, 16), // Wed
      DateTime(2026, 9, 18), // Fri
      DateTime(2026, 9, 19), // Sat
      DateTime(2026, 9, 20), // Sun
    ]) {
      final milo = RewardLedger.fromJson(demo('Milo').rewards(anchor));
      final nora = RewardLedger.fromJson(demo('Nora').rewards(anchor));
      final pearl =
          RewardLedger.fromJson(demo('Pearl').rewards(anchor));
      expect(
        milo.currentStreak(now: anchor, calendar: _calendarOf(demo('Milo'), anchor)),
        7,
        reason: 'Milo on $anchor',
      );
      expect(milo.totalPoints, 179, reason: 'Milo on $anchor');
      expect(nora.currentStreak(now: anchor), 2, reason: 'Nora on $anchor');
      // Milo's run only reaches 7 because the sick day is excused; scored
      // against the bare calendar it stops dead at the hole.
      expect(milo.currentStreak(now: anchor), 4,
          reason: 'Milo unexcused on $anchor');
      expect(pearl.currentStreak(now: anchor), 1, reason: 'Pearl on $anchor');
      expect(pearl.bestStreak(), 2, reason: 'Pearl on $anchor');
    }
  });

  test('seeded check-ins are priced the way the app would have priced them',
      () {
    final anchor = DateTime.now();
    for (final student in demoStudents) {
      final events = RewardLedger.fromJson(student.rewards(anchor)).events;
      final calendar = _calendarOf(student, anchor);
      // Replay the ledger in order; each visit has to match what the streak
      // it was standing on would have paid.
      var replayed = RewardLedger.empty;
      for (final e in events) {
        if (e.kind == RewardKind.visit) {
          final day =
              replayed.streakAfterActivityOn(e.at.toLocal(), calendar: calendar);
          expect(
            e.points,
            visitPoints(day),
            reason: '${student.name} ${e.id} should pay day-$day rate',
          );
        }
        replayed = replayed.add(e);
      }
    }
  });

  test('seeded reward ids match the keys the app would award against', () async {
    final ledger = RewardLedger.fromJson(await store.readRewards('990001'));
    final statuses = studentNamed('Milo').assignmentStatus;
    // Every id built off a real assignment key has to name a key that exists,
    // or re-doing that action in the app would pay a second time.
    // Visits key on a date and teacher emails on a course, so only the
    // assignment-keyed ids are checkable here; `demo-h*` are stand-ins for
    // work that has aged out of the payload entirely.
    final assignmentIds = ledger.events
        .map((e) => e.id)
        .where((id) => !id.contains('demo-h'))
        .where((id) => !id.startsWith('teacherEmail:'))
        .where((id) => !id.startsWith('visit:'));
    expect(assignmentIds, isNotEmpty);
    for (final id in assignmentIds) {
      final key = id.substring(id.indexOf(':') + 1);
      expect(statuses.containsKey(key), isTrue, reason: 'unknown key in $id');
    }
  });

  test('clearDemoData empties the store but keeps credentials', () async {
    await store.writeCredentials({'canvas_token': 'keep-me'});
    await clearDemoData(store);
    expect(await store.readCanvasData(), isNull);
    expect(await store.readSynergyData(), isNull);
    expect((await store.readCredentials())?['canvas_token'], 'keep-me');

    // Restore for any later run in the same process.
    await seedDemoData(store);
  });
}

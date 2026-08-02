// Verifies the demo seed actually produces something worth looking at:
// it round-trips through LocalStore + DataAssembler (the real read path), the
// dates land inside the dashboard's default window, and the seeded local
// statuses attach to the assignments they name.
//
// path_provider has no implementation under `flutter test`, so the platform
// interface is stubbed to hand back a temp directory.

import 'dart:io';

import 'package:assignment_tracker_app/dev/demo_seed.dart';
import 'package:assignment_tracker_app/domain/data_assembler.dart';
import 'package:assignment_tracker_app/domain/merged.dart';
import 'package:assignment_tracker_app/domain/priority.dart';
import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:assignment_tracker_app/storage/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

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

  test('seeds two students with courses on both sides', () {
    expect(payload.students.map((s) => s.name), ['Student', 'Nora']);
    final student = payload.students.first;
    expect(student.synergy!.courses, hasLength(5));
    expect(student.canvas!.courses, hasLength(2));
  });

  test('Canvas courses merge into their Synergy counterparts', () {
    final student = payload.students.first;
    final merged = mergeData(student.canvas, student.synergy);
    // One merged course per Synergy course — no orphaned Canvas-only courses.
    expect(merged, hasLength(5));

    final math = merged.firstWhere((c) => c.name == 'Accelerated Math 6');
    expect(
      math.items.any((i) => i.source == 'both'),
      isTrue,
      reason: 'name similarity should link Canvas rows to Synergy rows',
    );
    expect(
      math.items.any((i) => i.source == 'canvas'),
      isTrue,
      reason: 'the unmatched Canvas row should survive as canvas-only',
    );
    expect(math.teacherEmail, 'ajames@demo.invalid');
  });

  test('every seeded date falls inside the default one-month window', () {
    final today = DateTime.now();
    final range = DateRange(
      start: DateTime(today.year, today.month - 1, today.day),
      end: DateTime(today.year, today.month + 1, today.day),
    );
    for (final s in payload.students) {
      for (final c in mergeData(s.canvas, s.synergy)) {
        for (final i in c.items) {
          expect(
            range.contains(i.date),
            isTrue,
            reason: '${c.name} / ${i.name} at ${i.date} is out of range',
          );
        }
      }
    }
  });

  test('the catch-up list is non-empty and led by the failing courses', () {
    final student = payload.students.first;
    final today = DateTime.now();
    final range = DateRange(
      start: DateTime(today.year, today.month - 1, today.day),
      end: DateTime(today.year, today.month + 1, today.day),
    );
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

    expect(ranked.length, greaterThan(5));
    // Language Arts is at 57% — the most distressed course, so it should own
    // the top slot ahead of Math at 63.5%.
    expect(ranked.first.$1, 'Language Arts 6');
    // PE is at 100% with nothing missing; it should contribute nothing.
    expect(ranked.any((r) => r.$1 == 'PE 6'), isFalse);
  });

  test('the score threshold pulls a low graded item into the list', () {
    final student = payload.students.first;
    expect(student.scoreThresholds['Language Arts 6'], 70);
    final la = mergeData(
      student.canvas,
      student.synergy,
    ).firstWhere((c) => c.name == 'Language Arts 6');
    // The vocab quiz is Canvas-only and scored 12/20 = 60%, under the 70%
    // threshold. Synergy-sourced graded rows flatten to 'ok' and are never
    // actionable, so the Canvas-only path is the one the threshold governs.
    final quiz = la.items.firstWhere((i) => i.name.startsWith('Vocabulary'));
    expect(quiz.status, 'graded');
    expect(isActionable(quiz, la.name, student.scoreThresholds), isTrue);
    expect(isActionable(quiz, la.name, const {}), isFalse);
  });

  test('seeded local statuses attach to real assignments', () {
    final student = payload.students.first;
    final byKey = {
      for (final c in mergeData(student.canvas, student.synergy))
        for (final i in c.items) i.key: i,
    };
    for (final entry in student.assignmentStatus.entries) {
      expect(
        byKey.containsKey(entry.key),
        isTrue,
        reason: 'orphaned status for ${entry.value.assignmentName}',
      );
    }

    // The status seeded onto the already-graded Essay 2 must be suppressed.
    final essay = byKey.values.firstWhere((i) => i.name.startsWith('Essay 2'));
    expect(getLocalStatus(essay, student.assignmentStatus), isNull);

    // ...while the one on a missing item shows through.
    final varExpr = byKey.values.firstWhere(
      (i) => i.name.contains('Write variable expressions'),
    );
    expect(
      getLocalStatus(varExpr, student.assignmentStatus)?.status,
      'planned',
    );
  });

  test('seeded comments attach to real assignments', () {
    final student = payload.students.first;
    final keys = {
      for (final c in mergeData(student.canvas, student.synergy))
        for (final i in c.items) i.key,
    };
    expect(student.comments, isNotEmpty);
    for (final key in student.comments.keys) {
      expect(keys.contains(key), isTrue, reason: 'orphaned comment on $key');
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

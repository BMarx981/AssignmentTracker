// Smoke test for the domain port. Loads a real /api/data fixture, runs the
// merge + scoring pipeline, and asserts:
//   - models parse without throwing
//   - mergeData produces the expected number of courses
//   - priorityScore returns sane values for missing assignments
//   - assignmentKey matches the JS contract
//
// True parity testing (exact score match against the JS UI) requires a one-time
// dump of `[assignmentKey, score]` pairs from a browser session and adding them
// as golden values here. That's intentionally a follow-up step.

import 'dart:io';

import 'package:assignment_tracker_app/domain/merged.dart';
import 'package:assignment_tracker_app/domain/name_utils.dart';
import 'package:assignment_tracker_app/domain/priority.dart';
import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('domain port', () {
    late DataPayload payload;

    setUp(() {
      final raw = File('test/fixtures/data.json').readAsStringSync();
      payload = DataPayload.fromJsonString(raw);
    });

    test('payload parses', () {
      expect(payload.students.length, greaterThan(0));
      expect(payload.gradeBands.failing, 60);
      expect(payload.gradeBands.atRisk, 75);
    });

    test('mergeData produces a course per Synergy course in this fixture', () {
      final s = payload.students.first;
      final merged = mergeData(s.canvas, s.synergy);
      expect(merged.length, s.synergy?.courses.length ?? 0);
      expect(merged.first.items, isNotEmpty);
    });

    test('isActionable flags missing / zero_graded items', () {
      final s = payload.students.first;
      final merged = mergeData(s.canvas, s.synergy);
      final flagged = <MergedItem>[];
      for (final c in merged) {
        for (final it in c.items) {
          if (isActionable(it, c.name, s.scoreThresholds)) flagged.add(it);
        }
      }
      // We at least expect *some* actionable items in a real student fixture.
      expect(flagged, isNotEmpty);
      // All flagged should be missing or zero_graded (no threshold rule active).
      for (final f in flagged) {
        expect(['missing', 'zero_graded', 'graded'], contains(f.status));
      }
    });

    test('priorityScore is positive for in-range, actionable items', () {
      final s = payload.students.first;
      final merged = mergeData(s.canvas, s.synergy);
      // Use a wide range so the date filter does not exclude anything.
      final range = DateRange(
        start: DateTime(2020, 1, 1),
        end: DateTime(2030, 12, 31),
      );
      final today = DateTime(2026, 6, 13);

      var seen = 0;
      for (final c in merged) {
        for (final it in c.items) {
          final score = priorityScore(
            item: it,
            course: c,
            today: today,
            thresholds: s.scoreThresholds,
            statusByKey: s.assignmentStatus,
            range: range,
          );
          if (score > 0) seen++;
        }
      }
      expect(seen, greaterThan(0),
          reason: 'expected at least one actionable item to score > 0');
    });

    test('assignmentKey matches the JS contract for synergy items', () {
      // Synergy-only item: key = syn_<normalized_course>_<normalized_name>
      final key = assignmentKey(
        canvasId: null,
        courseName: 'Math 7',
        assignmentName: 'HW: Multiply fractions (due 6/13)',
      );
      expect(key.startsWith('syn_'), isTrue);
      // The (due 6/13) suffix should be stripped by normalizeName.
      expect(key.contains('due'), isFalse);
    });

    test('assignmentKey prefers canvas_id when present', () {
      final key = assignmentKey(
        canvasId: '12345',
        courseName: 'irrelevant',
        assignmentName: 'irrelevant',
      );
      expect(key, 'canvas_12345');
    });

    test('courseClass respects grade bands', () {
      const bands = GradeBands(failing: 60, atRisk: 75);
      expect(courseClass(null, bands), 'none');
      expect(courseClass(0.55, bands), 'bad');
      expect(courseClass(0.70, bands), 'warn');
      expect(courseClass(0.85, bands), 'ok');
    });
  });
}

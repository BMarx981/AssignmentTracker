import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:assignment_tracker_app/domain/assignment_situation.dart';
import 'package:assignment_tracker_app/domain/merged.dart';
import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:assignment_tracker_app/util/format.dart';
import 'package:assignment_tracker_app/widgets/assignment_actions_sheet.dart';

import '../support/harness.dart';

const _item = MergedItem(
  source: 'synergy',
  name: 'Chapter 4 problems',
  date: '2026-05-01',
  pointsPossible: 20,
  status: 'missing',
  courseName: 'Algebra',
);

const _course = MergedCourse(
  name: 'Algebra',
  teacher: 'Reyes, Dana',
  teacherEmail: 'dreyes@example.edu',
);

LocalStatus _status(String status, {String? plannedDate}) => LocalStatus(
      status: status,
      assignmentName: _item.name,
      courseName: _item.courseName,
      plannedDate: plannedDate,
    );

/// Pumps the panel and reports whether a terminal action closed it.
Future<bool Function()> _pumpSheet(
  WidgetTester tester, {
  required Student student,
  required ActionLog log,
}) async {
  var dismissed = false;
  await pumpHarness(
    tester,
    student: student,
    log: log,
    child: AssignmentActionsSheet(
      item: _item,
      course: _course,
      onDone: () => dismissed = true,
    ),
  );
  return () => dismissed;
}

void main() {
  group('fresh assignment', () {
    testWidgets('opens with the plan group expanded and the rest collapsed',
        (tester) async {
      await _pumpSheet(tester, student: testStudent(), log: ActionLog());

      // All three group labels are readable at rest.
      expect(find.text('Plan it'), findsOneWidget);
      expect(find.text('I already did it'), findsOneWidget);
      expect(find.text("Something's off about this"), findsOneWidget);

      // The dominant branch is already open — planning costs one tap.
      expect(find.text('Tonight'), findsOneWidget);
      expect(find.text('Tomorrow'), findsOneWidget);
      expect(find.text('Weekend'), findsOneWidget);
      expect(find.text('Pick a date…'), findsOneWidget);

      // The rarer branches stay behind their labels.
      expect(find.text('Turned it in'), findsNothing);
      expect(find.text('Remind me to ask teacher'), findsNothing);
    });

    testWidgets('no current-state header when nothing is recorded',
        (tester) async {
      await _pumpSheet(tester, student: testStudent(), log: ActionLog());
      expect(find.text('Change'), findsNothing);
      expect(find.text('Clear'), findsNothing);
    });

    testWidgets('planning writes a dated status and closes the sheet',
        (tester) async {
      final log = ActionLog();
      final dismissed = await _pumpSheet(
        tester,
        student: testStudent(),
        log: log,
      );

      await tester.tap(find.text('Tomorrow'));
      await tester.pumpAndSettle();

      final tomorrow = ymd(DateTime.now().add(const Duration(days: 1)));
      expect(log.statuses, ['planned:$tomorrow']);
      expect(dismissed(), isTrue);
    });
  });

  group('branch disclosure', () {
    testWidgets('opening "I already did it" swaps out the plan chips',
        (tester) async {
      await _pumpSheet(tester, student: testStudent(), log: ActionLog());

      await tester.tap(find.text('I already did it'));
      await tester.pumpAndSettle();

      expect(find.text('Turned it in'), findsOneWidget);
      expect(find.text('Done, not turned in yet'), findsOneWidget);
      expect(find.text('Tonight'), findsNothing);
    });

    testWidgets('each "already did it" option writes its own status',
        (tester) async {
      final log = ActionLog();
      await _pumpSheet(tester, student: testStudent(), log: log);

      await tester.tap(find.text('I already did it'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done, not turned in yet'));
      await tester.pumpAndSettle();

      expect(log.statuses, ['complete_pending_submission']);
    });

    testWidgets('"Something\'s off" reveals the three flags with subtitles',
        (tester) async {
      await _pumpSheet(tester, student: testStudent(), log: ActionLog());

      await tester.tap(find.text("Something's off about this"));
      await tester.pumpAndSettle();

      expect(find.text('Thought I handed it in'), findsOneWidget);
      expect(find.text('Remind me to ask teacher'), findsOneWidget);
      expect(find.text('Not sure'), findsOneWidget);
      // The rename carries an explanation of what it actually does.
      expect(
        find.text('Adds this to your teacher check-in list.'),
        findsOneWidget,
      );
      expect(find.text('Tonight'), findsNothing);
    });

    testWidgets('the teacher reminder posts the flag and keeps the panel open',
        (tester) async {
      final log = ActionLog();
      final dismissed = await _pumpSheet(
        tester,
        student: testStudent(),
        log: log,
      );

      await tester.tap(find.text("Something's off about this"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remind me to ask teacher'));
      await tester.pumpAndSettle();

      expect(log.posted, [kTeacherCheckInNote]);
      expect(log.statuses, isEmpty);
      // It composes with "thought I handed it in", so it must not dismiss.
      expect(dismissed(), isFalse);
    });

    testWidgets('"Not sure" flags for follow-up and exits', (tester) async {
      final log = ActionLog();
      final dismissed = await _pumpSheet(
        tester,
        student: testStudent(),
        log: log,
      );

      await tester.tap(find.text("Something's off about this"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not sure'));
      await tester.pumpAndSettle();

      expect(log.posted, [kNotSureNote]);
      // No status is forced on the student.
      expect(log.statuses, isEmpty);
      expect(dismissed(), isTrue);
    });

    testWidgets('tapping an open group label collapses it', (tester) async {
      await _pumpSheet(tester, student: testStudent(), log: ActionLog());

      await tester.tap(find.text('Plan it'));
      await tester.pumpAndSettle();

      expect(find.text('Tonight'), findsNothing);
      expect(find.text('Plan it'), findsOneWidget);
    });
  });

  group('reopening an assignment with a recorded state', () {
    testWidgets('a status claim opens on its header, not the chooser',
        (tester) async {
      await _pumpSheet(
        tester,
        student: testStudent(
          assignmentStatus: {
            _item.key: _status('submitted_pending_feedback'),
          },
        ),
        log: ActionLog(),
      );

      expect(find.text('Turned in, waiting on a grade'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      // Opened on the group the answer came from.
      expect(find.text('Turned it in'), findsOneWidget);
      expect(find.text('Tonight'), findsNothing);
    });

    testWidgets('a planned date shows in the header', (tester) async {
      await _pumpSheet(
        tester,
        student: testStudent(
          assignmentStatus: {
            _item.key: _status('planned', plannedDate: '2026-05-08'),
          },
        ),
        log: ActionLog(),
      );

      expect(find.text('Planned for Fri 5/8'), findsOneWidget);
      expect(find.text('Tonight'), findsOneWidget);
    });

    testWidgets('"thought I handed it in" reopens as the current state',
        (tester) async {
      await _pumpSheet(
        tester,
        student: testStudent(
          comments: {
            _item.key: [testNote(kThoughtHandedInNote)],
          },
        ),
        log: ActionLog(),
      );

      expect(find.text('You thought this was handed in'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      // Its group is open with the flag already marked set.
      expect(find.text('Thought I handed it in'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsWidgets);
      expect(find.text('Tonight'), findsNothing);
      // A bare flag carries no status, so there's nothing to clear.
      expect(find.text('Clear'), findsNothing);
    });

    testWidgets('Change drops the header and returns to the chooser',
        (tester) async {
      await _pumpSheet(
        tester,
        student: testStudent(
          assignmentStatus: {
            _item.key: _status('submitted_pending_feedback'),
          },
        ),
        log: ActionLog(),
      );

      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();

      expect(find.text('Turned in, waiting on a grade'), findsNothing);
      expect(find.text('Change'), findsNothing);
      // Back to the fresh view, plan group expanded.
      expect(find.text('Tonight'), findsOneWidget);
      expect(find.text('Turned it in'), findsNothing);
    });

    testWidgets('Clear wipes the status claim and closes the sheet',
        (tester) async {
      final log = ActionLog();
      final dismissed = await _pumpSheet(
        tester,
        student: testStudent(
          assignmentStatus: {_item.key: _status('planned')},
        ),
        log: log,
      );

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(log.statuses, ['clear']);
      expect(dismissed(), isTrue);
    });

    testWidgets('re-tapping a set flag clears it instead of posting again',
        (tester) async {
      final log = ActionLog();
      await _pumpSheet(
        tester,
        student: testStudent(
          comments: {
            _item.key: [testNote(kTeacherCheckInNote, id: 'flag-1')],
          },
        ),
        log: log,
      );

      await tester.tap(find.text('Remind me to ask teacher'));
      await tester.pumpAndSettle();

      expect(log.deleted, ['flag-1']);
      expect(log.posted, isEmpty);
    });

    testWidgets('a flag that grew replies is left alone', (tester) async {
      final log = ActionLog();
      await _pumpSheet(
        tester,
        student: testStudent(
          comments: {
            _item.key: [
              testNote(
                kTeacherCheckInNote,
                id: 'flag-1',
                replies: const [
                  CommentReply(
                    id: 'r1',
                    text: 'emailed them Tuesday',
                    author: 'me',
                    createdAt: '2026-05-02T00:00:00Z',
                  ),
                ],
              ),
            ],
          },
        ),
        log: log,
      );

      await tester.tap(find.text('Remind me to ask teacher'));
      await tester.pumpAndSettle();

      // Deleting the marker would take the reply with it.
      expect(log.deleted, isEmpty);
      expect(log.posted, isEmpty);
    });

    testWidgets('the done-but-not-submitted state nudges toward turning it in',
        (tester) async {
      await _pumpSheet(
        tester,
        student: testStudent(
          assignmentStatus: {
            _item.key: _status('complete_pending_submission'),
          },
        ),
        log: ActionLog(),
      );

      expect(find.text('Done, but not turned in yet'), findsOneWidget);
      expect(
        find.text('Turned it in since then? Tap "Turned it in".'),
        findsOneWidget,
      );
      expect(find.text('Turned it in'), findsOneWidget);
    });
  });
}

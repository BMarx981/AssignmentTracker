import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:assignment_tracker_app/domain/merged.dart';
import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:assignment_tracker_app/widgets/catch_up_row.dart';

import '../support/harness.dart';

const _item = MergedItem(
  source: 'synergy',
  name: 'Chapter 4 problems',
  date: '2026-05-01',
  pointsPossible: 20,
  status: 'missing',
  courseName: 'Algebra',
);

const _course = MergedCourse(name: 'Algebra');

LocalStatus _planned(String date) => LocalStatus(
      status: 'planned',
      assignmentName: _item.name,
      courseName: _item.courseName,
      plannedDate: date,
    );

Future<void> _pumpRow(
  WidgetTester tester, {
  required ActionLog log,
  Map<String, LocalStatus> statusByKey = const {},
}) =>
    pumpHarness(
      tester,
      student: testStudent(assignmentStatus: statusByKey),
      log: log,
      child: CatchUpRow(
        item: _item,
        course: _course,
        statusByKey: statusByKey,
      ),
    );

void main() {
  testWidgets('swiping right marks the assignment turned in', (tester) async {
    final log = ActionLog();
    await _pumpRow(tester, log: log);

    await tester.drag(find.byType(CatchUpRow), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(log.statuses, ['submitted_pending_feedback']);
    // The row itself survives — the data refresh is what drops it.
    expect(find.byType(CatchUpRow), findsOneWidget);
  });

  testWidgets('the mark-done swipe offers an undo', (tester) async {
    final log = ActionLog();
    await _pumpRow(tester, log: log);

    await tester.drag(find.byType(CatchUpRow), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('undo restores the previous claim rather than clearing it',
      (tester) async {
    final log = ActionLog();
    await _pumpRow(
      tester,
      log: log,
      statusByKey: {_item.key: _planned('2026-05-08')},
    );

    await tester.drag(find.byType(CatchUpRow), const Offset(500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    // The plan date the student had set survives the round trip.
    expect(log.statuses, ['submitted_pending_feedback', 'planned:2026-05-08']);
  });

  testWidgets('undo on an untouched assignment clears it', (tester) async {
    final log = ActionLog();
    await _pumpRow(tester, log: log);

    await tester.drag(find.byType(CatchUpRow), const Offset(500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(log.statuses, ['submitted_pending_feedback', 'clear']);
  });

  testWidgets('swiping left opens the full action sheet', (tester) async {
    final log = ActionLog();
    await _pumpRow(tester, log: log);

    await tester.drag(find.byType(CatchUpRow), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Plan it'), findsOneWidget);
    expect(find.text('Tonight'), findsOneWidget);
    // Swiping to the sheet writes nothing on its own.
    expect(log.statuses, isEmpty);
  });

  testWidgets('tapping the row still opens the sheet', (tester) async {
    await _pumpRow(tester, log: ActionLog());

    await tester.tap(find.text('Chapter 4 problems'));
    await tester.pumpAndSettle();

    expect(find.text('Plan it'), findsOneWidget);
  });
}

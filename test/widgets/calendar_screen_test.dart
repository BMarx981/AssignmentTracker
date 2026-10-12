// The calendar screen end to end against an in-memory student: today's
// entries show up under the grid, the filter sheet hides a class, the notice
// it raises clears it again, and a one-class calendar shows only that class.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:assignment_tracker_app/screens/calendar_screen.dart';
import 'package:assignment_tracker_app/state/data_providers.dart';
import 'package:assignment_tracker_app/theme/app_theme.dart';
import 'package:assignment_tracker_app/util/format.dart';

class _FakeDataNotifier extends DataNotifier {
  _FakeDataNotifier(this._payload);
  final DataPayload _payload;

  @override
  Future<DataPayload> build() async => _payload;
}

Map<String, dynamic> _course(int id, String name, String assignment,
        {List<Map<String, dynamic>> events = const []}) =>
    {
      'id': id,
      'name': name,
      'assignments': [
        {
          'id': id * 10,
          'name': assignment,
          'due_date': ymd(DateTime.now()),
          'points_possible': 10,
          'submission': {'workflow_state': 'graded', 'score': 9},
        },
      ],
      'events': events,
    };

Student _student() {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day, 15);
  return Student(
    studentId: 's1',
    name: 'Kid',
    canvas: CanvasData.fromJson({
      'courses': [
        _course(1, 'Math', 'Ratio worksheet', events: [
          {
            'id': 70,
            'title': 'Unit 4 Test',
            'start_at': start.toUtc().toIso8601String(),
            'end_at':
                start.add(const Duration(hours: 1)).toUtc().toIso8601String(),
          },
        ]),
        _course(2, 'Art', 'Self-portrait sketch'),
      ],
    }),
  );
}

Future<void> _pump(WidgetTester tester, {String? courseName}) async {
  SharedPreferences.setMockInitialValues({});
  // Wide enough for the side-by-side layout, so the day list is on screen.
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      dataProvider.overrideWith(() => _FakeDataNotifier(DataPayload(
            students: [_student()],
            gradeBands: const GradeBands(failing: 60, atRisk: 75),
          ))),
    ],
    child: MaterialApp(
      theme: buildLightTheme(),
      home: CalendarScreen(courseName: courseName),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('today lists events first, then each class\'s assignments',
      (tester) async {
    await _pump(tester);
    expect(find.text('Unit 4 Test'), findsOneWidget);
    expect(find.text('Ratio worksheet'), findsOneWidget);
    expect(find.text('Self-portrait sketch'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Unit 4 Test')).dy,
      lessThan(tester.getTopLeft(find.text('Ratio worksheet')).dy),
    );
  });

  testWidgets('hiding a class in the filter sheet hides its work',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Art'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20)); // dismiss the sheet
    await tester.pumpAndSettle();

    expect(find.text('Self-portrait sketch'), findsNothing);
    expect(find.text('Ratio worksheet'), findsOneWidget);
    expect(find.text('Filters are hiding some items.'), findsOneWidget);

    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();
    expect(find.text('Self-portrait sketch'), findsOneWidget);
    expect(find.text('Filters are hiding some items.'), findsNothing);
  });

  testWidgets('hiding events leaves assignments', (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Canvas events'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('Unit 4 Test'), findsNothing);
    expect(find.text('Ratio worksheet'), findsOneWidget);
  });

  testWidgets('a one-class calendar shows only that class', (tester) async {
    await _pump(tester, courseName: 'Math');
    expect(find.text('Unit 4 Test'), findsOneWidget);
    expect(find.text('Ratio worksheet'), findsOneWidget);
    expect(find.text('Self-portrait sketch'), findsNothing);

    // Its filter sheet has no class section: the class is the page.
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    expect(find.text('CLASSES'), findsNothing);
  });
}

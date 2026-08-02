// The gate is the whole point of the screen: a student who taps into Parent
// controls must not reach the excused-day button. These drive it the way he
// would — by guessing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:assignment_tracker_app/screens/parent_controls_screen.dart';
import 'package:assignment_tracker_app/state/excused_days_providers.dart';
import 'package:assignment_tracker_app/state/parent_gate_provider.dart';
import 'package:assignment_tracker_app/state/student_providers.dart';
import 'package:assignment_tracker_app/storage/parent_gate_store.dart';
import 'package:assignment_tracker_app/theme/app_theme.dart';

/// In-memory stand-in for the real store, so these never touch the disk and
/// never pay for 100k rounds of SHA-256.
class _FakeGate implements ParentGateStore {
  _FakeGate([this._passcode]);

  String? _passcode;

  @override
  Future<bool> isConfigured() async => _passcode != null;

  @override
  Future<void> setPasscode(String passcode) async => _passcode = passcode;

  @override
  Future<bool> verify(String passcode) async =>
      _passcode != null && passcode == _passcode;

  @override
  Future<void> clear() async => _passcode = null;
}

void main() {
  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    required ParentGateStore gate,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          parentGateStoreProvider.overrideWithValue(gate),
          selectedStudentProvider.overrideWithValue(
            const AsyncData(Student(studentId: 's1', name: 'Milo')),
          ),
          excusedDaysProvider('s1')
              .overrideWith(() => _StubExcusedDays()),
        ],
        child: MaterialApp(
          theme: buildDarkTheme(),
          home: const ParentControlsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(ParentControlsScreen)),
    );
  }

  testWidgets('with no passcode set, it asks for one to be created',
      (tester) async {
    await pumpScreen(tester, gate: _FakeGate());

    expect(find.text('Set a parent passcode'), findsOneWidget);
    // Nothing behind the gate is reachable yet.
    expect(find.text('Excuse a day'), findsNothing);
  });

  testWidgets('a new passcode has to be typed twice and be long enough',
      (tester) async {
    final gate = _FakeGate();
    await pumpScreen(tester, gate: gate);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '123');
    await tester.enterText(fields.at(1), '123');
    await tester.tap(find.text('Set passcode'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 4 characters.'), findsOneWidget);
    expect(await gate.isConfigured(), isFalse);

    await tester.enterText(fields.at(0), 'letmein');
    await tester.enterText(fields.at(1), 'letmeout');
    await tester.tap(find.text('Set passcode'));
    await tester.pumpAndSettle();
    expect(find.text("Those don't match."), findsOneWidget);
    expect(await gate.isConfigured(), isFalse);
  });

  testWidgets('setting the passcode unlocks it for whoever set it',
      (tester) async {
    final gate = _FakeGate();
    await pumpScreen(tester, gate: gate);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'letmein');
    await tester.enterText(fields.at(1), 'letmein');
    await tester.tap(find.text('Set passcode'));
    await tester.pumpAndSettle();

    expect(await gate.isConfigured(), isTrue);
    expect(find.text('Excuse a day'), findsOneWidget);
  });

  testWidgets('an existing passcode locks the excused-day controls away',
      (tester) async {
    await pumpScreen(tester, gate: _FakeGate('letmein'));

    expect(find.text('Parent passcode'), findsOneWidget);
    expect(find.text('Excuse a day'), findsNothing);
    expect(find.text('Change passcode'), findsNothing);
  });

  testWidgets('a wrong guess says how many are left and opens nothing',
      (tester) async {
    await pumpScreen(tester, gate: _FakeGate('letmein'));

    await tester.enterText(find.byType(TextField), 'password');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text("That's not it. 4 tries left."), findsOneWidget);
    expect(find.text('Excuse a day'), findsNothing);
  });

  testWidgets('the right passcode opens the excused-day controls',
      (tester) async {
    await pumpScreen(tester, gate: _FakeGate('letmein'));

    await tester.enterText(find.byType(TextField), 'letmein');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('Excused days'), findsOneWidget);
    expect(find.text('Excuse a day'), findsOneWidget);
    expect(find.text('Change passcode'), findsOneWidget);
  });

  testWidgets('guessing repeatedly locks it out entirely', (tester) async {
    await pumpScreen(tester, gate: _FakeGate('letmein'));

    for (var i = 0; i < 5; i++) {
      await tester.enterText(find.byType(TextField), 'guess$i');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
    }
    expect(
      find.text('Too many tries. Wait a minute and try again.'),
      findsOneWidget,
    );

    // Even the correct passcode is refused while the cooldown runs, so a kid
    // who eventually shoulder-surfs it still can't walk straight in.
    await tester.enterText(find.byType(TextField), 'letmein');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Excuse a day'), findsNothing);
  });

  testWidgets('locking it again puts the passcode prompt back', (tester) async {
    await pumpScreen(tester, gate: _FakeGate('letmein'));

    await tester.enterText(find.byType(TextField), 'letmein');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Excuse a day'), findsOneWidget);

    await tester.tap(find.byTooltip('Lock'));
    await tester.pumpAndSettle();
    expect(find.text('Parent passcode'), findsOneWidget);
    expect(find.text('Excuse a day'), findsNothing);
  });
}

/// Keeps the excused-days family off the filesystem — these tests are about
/// the gate, not about persistence.
class _StubExcusedDays extends ExcusedDaysNotifier {
  _StubExcusedDays() : super('s1');

  @override
  Future<List<ExcusedDay>> build() async => const [];
}

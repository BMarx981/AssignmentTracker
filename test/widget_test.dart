import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:assignment_tracker_app/main.dart';

void main() {
  testWidgets('App scaffolds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: TrackerApp()));
    expect(find.text('Assignment Tracker'), findsOneWidget);
  });
}

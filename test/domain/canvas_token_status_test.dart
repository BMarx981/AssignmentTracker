import 'package:flutter_test/flutter_test.dart';

import 'package:assignment_tracker_app/domain/canvas_token_status.dart';

void main() {
  final now = DateTime(2026, 10, 12, 9);
  // Canvas sends UTC (MCPS: 05:00Z, i.e. local midnight). Build it from a
  // local date so the day counts hold in whatever zone the tests run in.
  final status = CanvasTokenStatus.fromJson(
      {'expires_at': DateTime(2027, 1, 10).toUtc().toIso8601String()});

  test('counts calendar days to the local expiry date', () {
    expect(status.daysLeft(now), 90);
    expect(status.needsAttention(now), isFalse);
    expect(status.describe(now), 'Expires Jan 10, 2027 (in 90 days)');
  });

  test('starts warning two weeks out', () {
    expect(status.needsAttention(DateTime(2026, 12, 26)), isFalse); // 15 days
    expect(status.needsAttention(DateTime(2026, 12, 27)), isTrue); // 14 days
  });

  test('describes the last days and after expiry', () {
    expect(status.describe(DateTime(2027, 1, 9, 23)),
        'Expires tomorrow (Jan 10, 2027)');
    expect(status.describe(DateTime(2027, 1, 10, 8)),
        'Expires today (Jan 10, 2027)');
    expect(status.describe(DateTime(2027, 1, 11)), 'Expired Jan 10, 2027');
  });

  test('a token without expires_at never needs attention', () {
    final forever = CanvasTokenStatus.fromJson({'expires_at': null});
    expect(forever.daysLeft(now), isNull);
    expect(forever.needsAttention(now), isFalse);
    expect(forever.describe(now), 'Never expires');
  });

  test('a rejected token always needs attention', () {
    const dead = CanvasTokenStatus(rejected: true);
    expect(dead.needsAttention(now), isTrue);
    expect(dead.describe(now), startsWith('Canvas rejected this token'));
  });
}

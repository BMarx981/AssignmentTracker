import 'package:flutter_test/flutter_test.dart';

import 'package:assignment_tracker_app/domain/calendar.dart';
import 'package:assignment_tracker_app/domain/merged.dart';
import 'package:assignment_tracker_app/models/api_models.dart';

final _today = DateTime(2026, 10, 12);

MergedItem _item(
  String name,
  String? date, {
  String status = 'graded',
  String? canvasStatus,
  String course = 'Math',
  double? score,
}) =>
    MergedItem(
      source: 'canvas',
      name: name,
      date: date,
      status: status,
      canvasStatus: canvasStatus,
      courseName: course,
      score: score,
      pointsPossible: score == null ? null : 10,
    );

CanvasEvent _event(
  String title, {
  DateTime? start,
  DateTime? end,
  String? allDayDate,
}) =>
    CanvasEvent(
      id: title,
      title: title,
      startAt: start,
      endAt: end,
      allDay: allDayDate != null,
      allDayDate: allDayDate,
    );

void main() {
  group('calendarStatusOf', () {
    CalendarStatus of(MergedItem it) => calendarStatusOf(it, _today);

    test('an unsubmitted item is upcoming through its due day, then missing',
        () {
      expect(of(_item('a', '2026-10-13', status: 'missing')),
          CalendarStatus.upcoming);
      expect(of(_item('a', '2026-10-12', status: 'missing')),
          CalendarStatus.upcoming);
      expect(of(_item('a', '2026-10-11', status: 'missing')),
          CalendarStatus.missing);
    });

    test('zeros and 50% credit read as missing', () {
      expect(of(_item('a', '2026-10-01', status: 'zero_graded')),
          CalendarStatus.missing);
      expect(of(_item('a', '2026-10-01', status: 'half_credit_missing')),
          CalendarStatus.missing);
    });

    test('turned in but ungraded is waiting, from either source', () {
      expect(of(_item('a', '2026-10-01', status: 'not_graded')),
          CalendarStatus.waiting);
      expect(of(_item('a', '2026-10-01', status: 'submitted_pending')),
          CalendarStatus.waiting);
      // A Synergy 'ok' row merged with a Canvas submission still awaiting a
      // grade goes by the Canvas side.
      expect(
          of(_item('a', '2026-10-01',
              status: 'ok', canvasStatus: 'submitted_pending')),
          CalendarStatus.waiting);
    });

    test('graded, ok and excused are graded; unknown only once scored', () {
      expect(of(_item('a', '2026-10-01')), CalendarStatus.graded);
      expect(of(_item('a', '2026-10-01', status: 'ok')),
          CalendarStatus.graded);
      expect(of(_item('a', '2026-10-01', status: 'excused')),
          CalendarStatus.graded);
      expect(of(_item('a', '2026-10-01', status: 'unknown')),
          CalendarStatus.waiting);
      expect(of(_item('a', '2026-10-01', status: 'unknown', score: 8)),
          CalendarStatus.graded);
    });
  });

  group('CanvasEvent.days', () {
    test('an all-day event uses Canvas\'s date as-is', () {
      // Midnight UTC would be the previous evening in the Americas.
      final e = _event('x',
          start: DateTime.utc(2026, 10, 14).toLocal(),
          allDayDate: '2026-10-14');
      expect(e.days, ['2026-10-14']);
    });

    test('a timed event spans each local day it touches', () {
      final e = _event('x',
          start: DateTime(2026, 10, 14, 8), end: DateTime(2026, 10, 16, 15));
      expect(e.days, ['2026-10-14', '2026-10-15', '2026-10-16']);
    });

    test('ending at midnight does not spill onto the next day', () {
      final e = _event('x',
          start: DateTime(2026, 10, 14, 20), end: DateTime(2026, 10, 15));
      expect(e.days, ['2026-10-14']);
    });

    test('a runaway end date is capped at two weeks', () {
      final e = _event('x',
          start: DateTime(2026, 10, 1, 8), end: DateTime(2027, 1, 1, 8));
      expect(e.days, hasLength(14));
    });
  });

  group('buildCalendar', () {
    final math = MergedCourse(
      name: 'Math',
      items: [
        _item('Quiz', '2026-10-14', status: 'missing'),
        _item('Old homework', '2026-10-01', status: 'missing'),
        _item('No date', null, status: 'missing'),
      ],
      events: [
        _event('Unit test', allDayDate: '2026-10-14'),
        _event('Tutoring', start: DateTime(2026, 10, 14, 15)),
      ],
    );
    final art = MergedCourse(
      name: 'Art',
      items: [_item('Sketch', '2026-10-14', course: 'Art')],
    );

    Map<String, List<CalendarEntry>> build(
      CalendarFilter filter, {
      String? only,
    }) =>
        buildCalendar([math, art],
            filter: filter, today: _today, onlyCourse: only);

    test('groups by day, events first, then assignments by class', () {
      final day = build(const CalendarFilter())['2026-10-14']!;
      expect(
        day.map((e) => e.event?.title ?? e.item!.name),
        ['Unit test', 'Tutoring', 'Sketch', 'Quiz'],
      );
      expect(build(const CalendarFilter()).keys,
          unorderedEquals(['2026-10-14', '2026-10-01']));
    });

    test('class, kind and status filters each narrow it', () {
      final noMath = build(const CalendarFilter(hiddenCourses: {'Math'}));
      expect(noMath.keys, ['2026-10-14']);
      expect(noMath['2026-10-14']!.single.item!.name, 'Sketch');

      final noEvents =
          build(const CalendarFilter(hiddenKinds: {CalendarKind.events}));
      expect(noEvents['2026-10-14']!.where((e) => e.event != null), isEmpty);

      final onlyMissing = build(const CalendarFilter(hiddenStatuses: {
        CalendarStatus.upcoming,
        CalendarStatus.waiting,
        CalendarStatus.graded,
      }));
      // Events have no status, so a status filter leaves them alone.
      expect(onlyMissing['2026-10-14']!.map((e) => e.event?.title ?? e.item!.name),
          ['Unit test', 'Tutoring']);
      expect(onlyMissing['2026-10-01']!.single.item!.name, 'Old homework');
    });

    test('a one-class calendar ignores the class filter', () {
      final cal = build(
        const CalendarFilter(hiddenCourses: {'Math'}),
        only: 'Math',
      );
      expect(cal['2026-10-14']!.map((e) => e.course.name).toSet(), {'Math'});
      expect(cal['2026-10-01'], isNotNull);
    });

    test('toggles round-trip back to the default filter', () {
      final f = const CalendarFilter()
          .toggleCourse('Math')
          .toggleKind(CalendarKind.events)
          .toggleStatus(CalendarStatus.graded);
      expect(f.isDefault, isFalse);
      expect(
        f
            .toggleCourse('Math')
            .toggleKind(CalendarKind.events)
            .toggleStatus(CalendarStatus.graded)
            .isDefault,
        isTrue,
      );
    });
  });

  test('class colors are assigned alphabetically, so they stay put', () {
    final slots = courseColorSlots(const [
      MergedCourse(name: 'Science'),
      MergedCourse(name: 'Art'),
      MergedCourse(name: 'Math'),
    ]);
    expect(slots, {'Art': 0, 'Math': 1, 'Science': 2});
  });
}

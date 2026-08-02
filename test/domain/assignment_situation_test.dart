import 'package:flutter_test/flutter_test.dart';

import 'package:assignment_tracker_app/domain/assignment_situation.dart';
import 'package:assignment_tracker_app/domain/merged.dart';
import 'package:assignment_tracker_app/models/api_models.dart';

const _item = MergedItem(
  source: 'synergy',
  name: 'Chapter 4 problems',
  date: '2026-05-01',
  pointsPossible: 20,
  status: 'missing',
  courseName: 'Algebra',
);

LocalStatus _status(String status, {String? plannedDate}) => LocalStatus(
      status: status,
      assignmentName: _item.name,
      courseName: _item.courseName,
      plannedDate: plannedDate,
    );

CommentThread _note(String text) =>
    CommentThread(id: 'c1', text: text, author: 'me', createdAt: '');

AssignmentSituation _resolve({
  LocalStatus? status,
  List<CommentThread> threads = const [],
}) =>
    resolveSituation(
      item: _item,
      statusByKey: status == null ? const {} : {_item.key: status},
      comments: threads.isEmpty ? const {} : {_item.key: threads},
    );

void main() {
  group('resolveSituation', () {
    test('nothing recorded yields no state', () {
      final s = _resolve();
      expect(s.state, isNull);
      expect(s.isRecorded, isFalse);
    });

    test('maps each status to its branch', () {
      expect(_resolve(status: _status('planned')).state, AssignmentState.planned);
      expect(
        _resolve(status: _status('complete_pending_submission')).state,
        AssignmentState.doneNotSubmitted,
      );
      expect(
        _resolve(status: _status('submitted_pending_feedback')).state,
        AssignmentState.submitted,
      );
    });

    test('planned summary includes the date', () {
      final s = _resolve(status: _status('planned', plannedDate: '2026-05-08'));
      expect(s.summary, 'Planned for Fri 5/8');
      expect(s.group, SheetGroup.plan);
    });

    test('legacy comment markers resolve without a status entry', () {
      final thought = _resolve(threads: [_note(kThoughtHandedInNote)]);
      expect(thought.state, AssignmentState.thoughtHandedIn);
      expect(thought.thoughtHandedIn, isTrue);
      expect(thought.group, SheetGroup.somethingsOff);

      final teacher = _resolve(threads: [_note(kTeacherCheckInNote)]);
      expect(teacher.state, AssignmentState.teacherCheckIn);
      expect(teacher.teacherCheckIn, isTrue);
    });

    test('the not-sure marker is picked up as its own state', () {
      final s = _resolve(threads: [_note(kNotSureNote)]);
      expect(s.state, AssignmentState.unsure);
      expect(s.unsure, isTrue);
      expect(s.group, SheetGroup.somethingsOff);
    });

    test('an explicit status outranks a flag', () {
      final s = _resolve(
        status: _status('submitted_pending_feedback'),
        threads: [_note(kThoughtHandedInNote), _note(kTeacherCheckInNote)],
      );
      expect(s.state, AssignmentState.submitted);
      expect(s.group, SheetGroup.alreadyDid);
      // The flags still read as set, they just don't drive the headline.
      expect(s.thoughtHandedIn, isTrue);
      expect(s.teacherCheckIn, isTrue);
    });

    test('a real grade suppresses the status claim, same as elsewhere', () {
      const graded = MergedItem(
        source: 'synergy',
        name: 'Chapter 4 problems',
        pointsPossible: 20,
        score: 18,
        status: 'graded',
        courseName: 'Algebra',
      );
      final s = resolveSituation(
        item: graded,
        statusByKey: {graded.key: _status('submitted_pending_feedback')},
        comments: const {},
      );
      expect(s.status, isNull);
      expect(s.state, isNull);
    });

    test('unrelated comments are not mistaken for flags', () {
      final s = _resolve(threads: [_note('ask mom for help')]);
      expect(s.state, isNull);
    });
  });
}

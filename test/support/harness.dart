// Shared widget-test scaffolding: a Student built in memory, a DataNotifier
// that serves it without touching the filesystem, and an AssignmentActions
// that records mutations instead of writing JSON.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:assignment_tracker_app/state/assignment_actions.dart';
import 'package:assignment_tracker_app/state/data_providers.dart';
import 'package:assignment_tracker_app/theme/app_theme.dart';
import 'package:assignment_tracker_app/util/format.dart';

/// Everything the recording actions saw, in call order.
class ActionLog {
  /// Status writes, as `status` or `status:YYYY-MM-DD` when a date came along.
  final List<String> statuses = [];

  /// Comment bodies posted (the flag markers).
  final List<String> posted = [];

  /// Comment ids deleted (clearing a flag).
  final List<String> deleted = [];
}

/// Stands in for the real [AssignmentActions]. Only the three write entry
/// points are overridden — `markSubmittedNow` and `clear` funnel through
/// `setStatus` in the base class, so they're covered too.
class RecordingActions extends AssignmentActions {
  RecordingActions(super.ref, this.log);

  final ActionLog log;

  @override
  Future<void> setStatus({
    required String key,
    required String status,
    required String assignmentName,
    required String courseName,
    DateTime? plannedDate,
    DateTime? submittedDate,
    bool award = true,
  }) async {
    log.statuses.add(
      plannedDate == null ? status : '$status:${ymd(plannedDate)}',
    );
  }

  @override
  Future<void> postComment({required String key, required String text}) async {
    log.posted.add(text);
  }

  @override
  Future<void> deleteComment({
    required String key,
    required String commentId,
    String? replyId,
  }) async {
    log.deleted.add(commentId);
  }
}

class _FakeDataNotifier extends DataNotifier {
  _FakeDataNotifier(this._payload);
  final DataPayload _payload;

  @override
  Future<DataPayload> build() async => _payload;
}

Student testStudent({
  Map<String, LocalStatus> assignmentStatus = const {},
  Map<String, List<CommentThread>> comments = const {},
}) =>
    Student(
      studentId: 's1',
      name: 'Test Student',
      assignmentStatus: assignmentStatus,
      comments: comments,
    );

CommentThread testNote(String text, {String id = 'c1', List<CommentReply> replies = const []}) =>
    CommentThread(
      id: id,
      text: text,
      author: 'me',
      createdAt: '2026-05-01T00:00:00Z',
      replies: replies,
    );

/// Pumps [child] under a ProviderScope wired to [student] and a
/// [RecordingActions] backed by [log], in the app's dark theme.
Future<void> pumpHarness(
  WidgetTester tester, {
  required Widget child,
  required Student student,
  required ActionLog log,
}) async {
  final payload = DataPayload(
    students: [student],
    gradeBands: const GradeBands(failing: 60, atRisk: 75),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dataProvider.overrideWith(() => _FakeDataNotifier(payload)),
        assignmentActionsProvider.overrideWith(
          (ref) => RecordingActions(ref, log),
        ),
      ],
      child: MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    ),
  );
  // dataProvider resolves a frame later; settle so the first real build sees it.
  await tester.pumpAndSettle();
}

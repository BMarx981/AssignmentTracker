// Helpers that mutate per-assignment state on the server, then refresh the
// data payload. All require the selected student so the server records the
// status against the right student bucket.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_models.dart';
import '../util/format.dart';
import 'api_providers.dart';
import 'data_providers.dart';
import 'student_providers.dart';

class AssignmentActions {
  final Ref _ref;
  AssignmentActions(this._ref);

  Future<String?> _studentId() async =>
      _ref.read(selectedStudentProvider).value?.studentId;

  Future<void> setStatus({
    required String key,
    required String status,
    required String assignmentName,
    required String courseName,
    DateTime? plannedDate,
    DateTime? submittedDate,
  }) async {
    final client = await _ref.read(apiClientProvider.future);
    await client.setAssignmentStatus(
      key,
      AssignmentStatusReq(
        status: status,
        assignmentName: assignmentName,
        courseName: courseName,
        studentId: await _studentId(),
        plannedDate: plannedDate != null ? ymd(plannedDate) : null,
        submittedDate: submittedDate != null ? ymd(submittedDate) : null,
      ),
    );
    await _ref.read(dataProvider.notifier).refresh();
  }

  /// "✅ already done" — submitted, no specific date.
  Future<void> markSubmittedNow({
    required String key,
    required String assignmentName,
    required String courseName,
  }) =>
      setStatus(
        key: key,
        status: 'submitted_pending_feedback',
        assignmentName: assignmentName,
        courseName: courseName,
      );

  Future<void> clear(String key) async {
    final client = await _ref.read(apiClientProvider.future);
    await client.setAssignmentStatus(
      key,
      AssignmentStatusReq(
        status: 'clear',
        assignmentName: '',
        courseName: '',
        studentId: await _studentId(),
      ),
    );
    await _ref.read(dataProvider.notifier).refresh();
  }

  /// Post a comment text and refresh the data payload (so the threads map
  /// on the Student object reflects the new entry).
  Future<void> postComment({
    required String key,
    required String text,
  }) async {
    final client = await _ref.read(apiClientProvider.future);
    await client.postComment(
      key,
      CommentReq(text: text, studentId: await _studentId()),
    );
    await _ref.read(dataProvider.notifier).refresh();
  }

  Future<void> postReply({
    required String key,
    required String parentId,
    required String text,
  }) async {
    final client = await _ref.read(apiClientProvider.future);
    await client.postComment(
      key,
      CommentReq(
          text: text, studentId: await _studentId(), replyToId: parentId),
    );
    await _ref.read(dataProvider.notifier).refresh();
  }

  Future<void> deleteComment({
    required String key,
    required String commentId,
    String? replyId,
  }) async {
    final client = await _ref.read(apiClientProvider.future);
    await client.deleteComment(
      key,
      commentId,
      studentId: await _studentId(),
      replyId: replyId,
    );
    await _ref.read(dataProvider.notifier).refresh();
  }
}

final assignmentActionsProvider =
    Provider<AssignmentActions>((ref) => AssignmentActions(ref));

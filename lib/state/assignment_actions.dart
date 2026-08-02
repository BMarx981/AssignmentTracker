// Per-assignment mutations: status changes and comment threads.
//
// Writes go straight to LocalStore (assignment_status.json / comments.json
// under students/<id>/), then refresh the dataProvider so the UI re-renders
// off the new files. No server round-trip.

import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:assignment_tracker_app/domain/rewards.dart';
import 'package:assignment_tracker_app/util/format.dart';
import 'api_providers.dart';
import 'data_providers.dart';
import 'rewards_providers.dart';
import 'student_providers.dart';

class AssignmentActions {
  AssignmentActions(this._ref);

  final Ref _ref;
  static final _rng = Random.secure();

  Future<String?> _studentId() async =>
      _ref.read(selectedStudentProvider).value?.studentId;

  // ---------- status ----------

  Future<void> setStatus({
    required String key,
    required String status,
    required String assignmentName,
    required String courseName,
    DateTime? plannedDate,
    DateTime? submittedDate,
    bool award = true,
  }) async {
    const allowed = {
      'planned',
      'complete_pending_submission',
      'submitted_pending_feedback',
    };
    if (status != 'clear' && !allowed.contains(status)) {
      throw ArgumentError('Unknown status: $status');
    }
    final sid = await _studentId();
    if (sid == null) return;

    final store = await _ref.read(localStoreProvider.future);
    final raw = await store.readAssignmentStatus(sid) ??
        <String, dynamic>{'entries': <String, dynamic>{}};
    final entries =
        (raw['entries'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    if (status == 'clear') {
      entries.remove(key);
    } else {
      entries[key] = <String, dynamic>{
        'status': status,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'assignment_name': assignmentName,
        'course_name': courseName,
        if (plannedDate != null) 'planned_date': ymd(plannedDate),
        if (submittedDate != null) 'submitted_date': ymd(submittedDate),
      };
    }

    await store.writeAssignmentStatus(sid, {'entries': entries});
    await _ref.read(dataProvider.notifier).refresh();

    if (award) {
      await _awardFor(
        status: status,
        key: key,
        assignmentName: assignmentName,
      );
    }
  }

  /// Hands out points for a status claim. Deduped on `<kind>:<assignmentKey>`
  /// inside the ledger, so clearing a status and re-setting it pays once —
  /// and clearing never takes points back.
  Future<void> _awardFor({
    required String status,
    required String key,
    required String assignmentName,
  }) async {
    final kind = switch (status) {
      'planned' => RewardKind.planned,
      'complete_pending_submission' => RewardKind.finished,
      'submitted_pending_feedback' => RewardKind.turnedIn,
      _ => null,
    };
    if (kind == null) return;
    await _ref.read(rewardServiceProvider).award(
          kind: kind,
          id: '${kind.name}:$key',
          label: assignmentName,
        );
  }

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

  Future<void> clear(String key) => setStatus(
        key: key,
        status: 'clear',
        assignmentName: '',
        courseName: '',
      );

  // ---------- comments ----------

  Future<void> postComment({
    required String key,
    required String text,
  }) =>
      _addComment(key: key, text: text, replyToId: null);

  Future<void> postReply({
    required String key,
    required String parentId,
    required String text,
  }) =>
      _addComment(key: key, text: text, replyToId: parentId);

  Future<void> _addComment({
    required String key,
    required String text,
    required String? replyToId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final sid = await _studentId();
    if (sid == null) return;

    final store = await _ref.read(localStoreProvider.future);
    final all = await store.readComments(sid) ?? <String, dynamic>{};
    final threadsRaw = (all[key] as List?) ?? const [];
    final threads = threadsRaw
        .map((t) => (t as Map).cast<String, dynamic>())
        .toList(growable: true);

    final now = DateTime.now().toUtc().toIso8601String();
    final id = _newId();

    if (replyToId == null) {
      threads.add(<String, dynamic>{
        'id': id,
        'text': trimmed,
        'author': 'me',
        'created_at': now,
        'replies': <Map<String, dynamic>>[],
      });
    } else {
      final parent = threads.firstWhere(
        (t) => t['id'] == replyToId,
        orElse: () => <String, dynamic>{},
      );
      if (parent.isEmpty) return;
      final replies = (parent['replies'] as List?)
              ?.map((r) => (r as Map).cast<String, dynamic>())
              .toList(growable: true) ??
          <Map<String, dynamic>>[];
      replies.add(<String, dynamic>{
        'id': id,
        'text': trimmed,
        'author': 'me',
        'created_at': now,
      });
      parent['replies'] = replies;
    }

    all[key] = threads;
    await store.writeComments(sid, all);
    await _ref.read(dataProvider.notifier).refresh();
  }

  Future<void> deleteComment({
    required String key,
    required String commentId,
    String? replyId,
  }) async {
    final sid = await _studentId();
    if (sid == null) return;

    final store = await _ref.read(localStoreProvider.future);
    final all = await store.readComments(sid) ?? <String, dynamic>{};
    final threadsRaw = (all[key] as List?) ?? const [];
    final threads = threadsRaw
        .map((t) => (t as Map).cast<String, dynamic>())
        .toList(growable: true);

    if (replyId == null) {
      threads.removeWhere((t) => t['id'] == commentId);
    } else {
      for (final t in threads) {
        if (t['id'] != commentId) continue;
        final replies = (t['replies'] as List?)
                ?.map((r) => (r as Map).cast<String, dynamic>())
                .toList(growable: true) ??
            <Map<String, dynamic>>[];
        replies.removeWhere((r) => r['id'] == replyId);
        t['replies'] = replies;
      }
    }

    if (threads.isEmpty) {
      all.remove(key);
    } else {
      all[key] = threads;
    }
    await store.writeComments(sid, all);
    await _ref.read(dataProvider.notifier).refresh();
  }

  String _newId() {
    final bytes = List<int>.generate(8, (_) => _rng.nextInt(256));
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}

final assignmentActionsProvider =
    Provider<AssignmentActions>((ref) => AssignmentActions(ref));

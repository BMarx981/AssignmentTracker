import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/merged.dart';
import '../domain/priority.dart';
import '../models/api_models.dart';
import '../state/assignment_actions.dart';
import '../state/student_providers.dart';
import 'status_badges.dart';

const _quickNotes = [
  ('🗣 Talk to teacher', 'Need to talk to teacher about this.'),
  ('📨 Thought I handed in', 'I thought this was done and handed in.'),
  (
    '⏳ Submitted, not graded',
    "I think this is handed in but it hasn't been graded yet."
  ),
];

class AssignmentCard extends ConsumerWidget {
  final MergedItem item;
  final MergedCourse course;
  final VoidCallback onShowComments;

  const AssignmentCard({
    super.key,
    required this.item,
    required this.course,
    required this.onShowComments,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final student = ref.watch(selectedStudentProvider).value;
    final thresholds = student?.scoreThresholds ?? const <String, int>{};
    final statusByKey = student?.assignmentStatus ?? const <String, LocalStatus>{};
    final actionable = isActionable(item, course.name, thresholds);
    final ls = getLocalStatus(item, statusByKey);
    final actions = ref.read(assignmentActionsProvider);
    final commentCount = student?.comments[item.key]?.length ?? 0;

    final pts = item.pointsPossible;
    final ptsStr = pts == null
        ? '—'
        : (pts == pts.roundToDouble()
            ? pts.toInt().toString()
            : pts.toStringAsFixed(1));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE3E3E3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text('$ptsStr pts',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A1A))),
            ],
          ),
          const SizedBox(height: 4),
          Text('due ${item.date ?? '?'}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
          if (statusBadgesFor(item, statusByKey).isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
                spacing: 4,
                runSpacing: 4,
                children: statusBadgesFor(item, statusByKey)),
          ],
          if (actionable) ...[
            const SizedBox(height: 10),
            _buildActionRow(context, ref, actions, ls),
            const SizedBox(height: 6),
            _buildStatusButtons(context, ref, actions, ls),
            const SizedBox(height: 6),
            _buildQuickNoteRow(context, ref, actions, student),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: onShowComments,
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: Text(commentCount > 0
                    ? '💬 $commentCount comments'
                    : '💬 Comments'),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow(BuildContext context, WidgetRef ref,
      AssignmentActions actions, LocalStatus? ls) {
    final planned = ls?.plannedDate;
    final submitted = ls?.status == 'submitted_pending_feedback';

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        planned != null
            ? _chip(
                '📅 Plan: $planned',
                background: const Color(0xFFD1FAE5),
                foreground: const Color(0xFF065F46),
                onTap: () => actions.clear(item.key),
                trailing: const Icon(Icons.close, size: 14),
              )
            : _buttonChip(
                '📅 Plan date',
                background: const Color(0xFFE0E7FF),
                foreground: const Color(0xFF1E3A8A),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now()
                        .subtract(const Duration(days: 30)),
                    lastDate:
                        DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    await actions.setStatus(
                      key: item.key,
                      status: 'planned',
                      assignmentName: item.name,
                      courseName: course.name,
                      plannedDate: picked,
                    );
                  }
                },
              ),
        submitted
            ? _chip(
                '✅ Submitted',
                background: const Color(0xFFD1FAE5),
                foreground: const Color(0xFF065F46),
                onTap: () => actions.clear(item.key),
                trailing: const Icon(Icons.close, size: 14),
              )
            : _buttonChip(
                '✅ Already done',
                background: const Color(0xFFE0E7FF),
                foreground: const Color(0xFF1E3A8A),
                onTap: () => actions.markSubmittedNow(
                  key: item.key,
                  assignmentName: item.name,
                  courseName: course.name,
                ),
              ),
      ],
    );
  }

  Widget _buildStatusButtons(BuildContext context, WidgetRef ref,
      AssignmentActions actions, LocalStatus? ls) {
    final cpActive = ls?.status == 'complete_pending_submission';
    final spActive = ls?.status == 'submitted_pending_feedback';
    final buttons = <Widget>[];
    if (ls == null || cpActive) {
      buttons.add(_outlineButton(
        cpActive ? '✓ Complete (pending submit)' : 'Mark complete · pending',
        onPressed: () async {
          if (cpActive) {
            await actions.clear(item.key);
          } else {
            await actions.setStatus(
              key: item.key,
              status: 'complete_pending_submission',
              assignmentName: item.name,
              courseName: course.name,
            );
          }
        },
        active: cpActive,
      ));
    }
    if (ls == null || spActive) {
      buttons.add(_outlineButton(
        spActive ? '✓ Submitted (awaiting grade)' : 'Mark submitted · awaiting',
        onPressed: () async {
          if (spActive) {
            await actions.clear(item.key);
          } else {
            await actions.setStatus(
              key: item.key,
              status: 'submitted_pending_feedback',
              assignmentName: item.name,
              courseName: course.name,
            );
          }
        },
        active: spActive,
      ));
    }
    if (ls != null) {
      buttons.add(_outlineButton(
        'Clear',
        onPressed: () => actions.clear(item.key),
      ));
    }
    return Wrap(spacing: 6, runSpacing: 6, children: buttons);
  }

  Widget _buildQuickNoteRow(BuildContext context, WidgetRef ref,
      AssignmentActions actions, Student? student) {
    final threads = student?.comments[item.key] ?? const <CommentThread>[];
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final note in _quickNotes)
          () {
            final (label, text) = note;
            final posted = threads.any((t) => t.text == text);
            return _buttonChip(
              posted ? '✓ $label' : label,
              background: posted
                  ? const Color(0xFFD1FAE5)
                  : const Color(0xFFF1F5F9),
              foreground:
                  posted ? const Color(0xFF065F46) : const Color(0xFF334155),
              onTap: () => actions.postComment(key: item.key, text: text),
            );
          }(),
      ],
    );
  }

  Widget _chip(
    String label, {
    required Color background,
    required Color foreground,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: foreground,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              IconTheme(
                  data: IconThemeData(color: foreground), child: trailing),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buttonChip(
    String label, {
    required Color background,
    required Color foreground,
    required VoidCallback onTap,
  }) =>
      _chip(label,
          background: background, foreground: foreground, onTap: onTap);

  Widget _outlineButton(String label,
      {required VoidCallback onPressed, bool active = false}) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor:
            active ? const Color(0xFFD1FAE5) : null,
        foregroundColor:
            active ? const Color(0xFF065F46) : const Color(0xFF1A1A1A),
        side: BorderSide(
            color: active
                ? const Color(0xFF065F46)
                : const Color(0xFFCBD5E1)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

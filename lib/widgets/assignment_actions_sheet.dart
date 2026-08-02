import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/merged.dart';
import '../domain/priority.dart';
import '../models/api_models.dart';
import '../state/assignment_actions.dart';
import '../state/student_providers.dart';
import '../theme/app_theme.dart';
import '../util/gmail_launcher.dart';

const _talkToTeacherLabel = '🗣 Talk to teacher';
const _talkToTeacherNote = 'Need to talk to teacher about this.';

const _quickNotes = [
  (_talkToTeacherLabel, _talkToTeacherNote),
  ('📨 Thought I handed in', 'I thought this was done and handed in.'),
  (
    '⏳ Submitted, not graded',
    "I think this is handed in but it hasn't been graded yet."
  ),
];

/// The plan/submit/quick-note action panel shared by the assignment card and
/// the catch-up row's bottom sheet. Renders nothing if the assignment isn't
/// actionable (caller should guard with [isActionable] if it wants to hide).
class AssignmentActionsSheet extends ConsumerWidget {
  final MergedItem item;
  final MergedCourse course;

  const AssignmentActionsSheet({
    super.key,
    required this.item,
    required this.course,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final student = ref.watch(selectedStudentProvider).value;
    final statusByKey =
        student?.assignmentStatus ?? const <String, LocalStatus>{};
    final ls = getLocalStatus(item, statusByKey);
    final actions = ref.read(assignmentActionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildActionRow(context, actions, ls),
        const SizedBox(height: 6),
        _buildStatusButtons(context, actions, ls),
        const SizedBox(height: 6),
        _buildQuickNoteRow(context, actions, student),
      ],
    );
  }

  Widget _buildActionRow(
      BuildContext context, AssignmentActions actions, LocalStatus? ls) {
    final colors = AppColors.of(context);
    final planned = ls?.plannedDate;
    final submitted = ls?.status == 'submitted_pending_feedback';

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        planned != null
            ? _chip(
                '📅 Plan: $planned',
                style: colors.success,
                onTap: () => actions.clear(item.key),
                trailing: const Icon(Icons.close, size: 14),
              )
            : _buttonChip(
                '📅 Plan date',
                style: colors.actionChip,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate:
                        DateTime.now().subtract(const Duration(days: 30)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
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
                style: colors.success,
                onTap: () => actions.clear(item.key),
                trailing: const Icon(Icons.close, size: 14),
              )
            : _buttonChip(
                '✅ Already done',
                style: colors.actionChip,
                onTap: () => actions.markSubmittedNow(
                  key: item.key,
                  assignmentName: item.name,
                  courseName: course.name,
                ),
              ),
      ],
    );
  }

  Widget _buildStatusButtons(
      BuildContext context, AssignmentActions actions, LocalStatus? ls) {
    final colors = AppColors.of(context);
    final cpActive = ls?.status == 'complete_pending_submission';
    final spActive = ls?.status == 'submitted_pending_feedback';
    final buttons = <Widget>[];
    if (ls == null || cpActive) {
      buttons.add(_outlineButton(
        colors,
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
        colors,
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
        colors,
        'Clear',
        onPressed: () => actions.clear(item.key),
      ));
    }
    return Wrap(spacing: 6, runSpacing: 6, children: buttons);
  }

  Widget _buildQuickNoteRow(
      BuildContext context, AssignmentActions actions, Student? student) {
    final colors = AppColors.of(context);
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
              style: posted ? colors.success : colors.neutralChip,
              onTap: () async {
                final messenger = ScaffoldMessenger.maybeOf(context);
                await actions.postComment(key: item.key, text: text);
                if (label == _talkToTeacherLabel) {
                  await _launchTeacherEmail(messenger, student);
                }
              },
            );
          }(),
      ],
    );
  }

  Future<void> _launchTeacherEmail(
      ScaffoldMessengerState? messenger, Student? student) async {
    final email = course.teacherEmail?.trim();
    if (email == null || email.isEmpty) {
      messenger?.showSnackBar(SnackBar(
        content: Text(course.teacher == null
            ? "No teacher email on file for this course."
            : "No email on file for ${course.teacher}."),
      ));
      return;
    }

    final subject = '${course.name}: ${item.name}';
    final body = _emailBody(student);
    final ok =
        await openGmailCompose(to: email, subject: subject, body: body);
    if (!ok) {
      messenger?.showSnackBar(
          const SnackBar(content: Text("Couldn't open Gmail compose window.")));
    }
  }

  String _emailBody(Student? student) {
    final teacherSalutation = _shortTeacherSalutation(course.teacher);
    final due = item.date == null ? '' : ' (due ${item.date})';
    final pts = item.pointsPossible;
    final ptsLabel = pts == null
        ? ''
        : ', ${pts == pts.roundToDouble() ? pts.toInt() : pts.toStringAsFixed(1)} pts';
    final signOff = (student?.name.isNotEmpty ?? false) ? student!.name : '';
    return 'Hi $teacherSalutation,\n\n'
        "I'm reaching out about ${item.name}$due$ptsLabel in ${course.name}.\n\n"
        "\n\n"
        'Thanks,\n$signOff';
  }

  String _shortTeacherSalutation(String? teacher) {
    if (teacher == null || teacher.trim().isEmpty) return 'there';
    final t = teacher.trim();
    final comma = RegExp(r'^([^,]+),').firstMatch(t);
    if (comma != null) return comma.group(1)!.trim();
    final parts = t.split(RegExp(r'\s+'));
    return parts.length > 1 ? parts.last : t;
  }

  Widget _chip(
    String label, {
    required BadgeStyle style,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: style.foreground,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              IconTheme(
                  data: IconThemeData(color: style.foreground),
                  child: trailing),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buttonChip(
    String label, {
    required BadgeStyle style,
    required VoidCallback onTap,
  }) =>
      _chip(label, style: style, onTap: onTap);

  Widget _outlineButton(AppColors colors, String label,
      {required VoidCallback onPressed, bool active = false}) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: active ? colors.success.background : null,
        foregroundColor:
            active ? colors.success.foreground : colors.textStrong,
        side: BorderSide(
            color: active ? colors.success.foreground : colors.border),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

/// Opens a modal bottom sheet with the assignment action panel. Used by the
/// catch-up row on the home screen so a student can resolve an item without
/// navigating away.
Future<void> showAssignmentActionsSheet(
  BuildContext context, {
  required MergedItem item,
  required MergedCourse course,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.of(context).card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 4,
            bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.name,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                course.name,
                style: TextStyle(
                    fontSize: 12, color: AppColors.of(ctx).textSecondary),
              ),
              const SizedBox(height: 12),
              AssignmentActionsSheet(item: item, course: course),
            ],
          ),
        ),
      );
    },
  );
}

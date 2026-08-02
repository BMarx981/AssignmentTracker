import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:assignment_tracker_app/domain/assignment_situation.dart';
import 'package:assignment_tracker_app/domain/merged.dart';
import 'package:assignment_tracker_app/domain/rewards.dart';
import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:assignment_tracker_app/router.dart';
import 'package:assignment_tracker_app/state/assignment_actions.dart';
import 'package:assignment_tracker_app/state/rewards_providers.dart';
import 'package:assignment_tracker_app/state/student_providers.dart';
import 'package:assignment_tracker_app/state/teacher_checkin_provider.dart';
import 'package:assignment_tracker_app/theme/app_theme.dart';
import 'package:assignment_tracker_app/util/format.dart';
import 'package:assignment_tracker_app/util/gmail_launcher.dart';

/// Everything the student flagged with "Remind me to ask teacher", grouped by
/// course so one conversation covers all of that teacher's items.
///
/// Composing the email lives here rather than on the flag itself: the flag is
/// a reminder for later, and firing a browser window the moment you tap it is
/// the opposite of that.
class TeacherCheckInScreen extends ConsumerWidget {
  const TeacherCheckInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(teacherCheckInsProvider);
    final colors = AppColors.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Teacher check-ins'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.back('/'),
        ),
      ),
      body: groups.isEmpty
          ? _EmptyState(colors: colors)
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                for (final group in groups)
                  _CourseGroup(group: group),
              ],
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.colors});
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 56, color: colors.iconMuted),
            const SizedBox(height: 16),
            const Text(
              'Nothing to ask about',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "Remind me to ask teacher" on an assignment and it shows '
              'up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourseGroup extends ConsumerWidget {
  const _CourseGroup({required this.group});
  final TeacherCheckIn group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final course = group.course;
    final teacher = course.teacher?.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            course.name,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.textStrong,
            ),
          ),
          if (teacher != null && teacher.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                teacher,
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ),
          const SizedBox(height: 10),
          for (final item in group.items)
            _CheckInRow(item: item, course: course),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _emailTeacher(context, ref),
              icon: const Icon(Icons.mail_outline, size: 16),
              label: Text(
                group.items.length == 1
                    ? 'Email teacher'
                    : 'Email teacher about all ${group.items.length}',
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _emailTeacher(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final student = ref.read(selectedStudentProvider).value;
    final course = group.course;
    final email = course.teacherEmail?.trim();

    if (email == null || email.isEmpty) {
      messenger?.showSnackBar(SnackBar(
        content: Text(course.teacher == null
            ? 'No teacher email on file for this course.'
            : 'No email on file for ${course.teacher}.'),
      ));
      return;
    }

    final subject = group.items.length == 1
        ? '${course.name}: ${group.items.first.name}'
        : '${course.name}: questions about ${group.items.length} assignments';
    final ok = await openGmailCompose(
      to: email,
      subject: subject,
      body: _emailBody(student),
    );
    if (!ok) {
      messenger?.showSnackBar(
        const SnackBar(content: Text("Couldn't open Gmail compose window.")),
      );
      return;
    }

    // Deliberately one thumbs-up per teacher per day: emailing about three
    // things in one message is one act of asking, and reopening the same
    // compose window twice shouldn't pay twice.
    await ref.read(rewardServiceProvider).award(
          kind: RewardKind.teacherEmail,
          id: 'teacherEmail:${course.name}:${ymd(DateTime.now())}',
          label: course.name,
        );
  }

  String _emailBody(Student? student) {
    final salutation = _shortTeacherSalutation(group.course.teacher);
    final lines = group.items.map((it) {
      final due = it.date == null ? '' : ' (due ${it.date})';
      final pts = it.pointsPossible;
      final ptsLabel = pts == null
          ? ''
          : ', ${pts == pts.roundToDouble() ? pts.toInt() : pts.toStringAsFixed(1)} pts';
      return '- ${it.name}$due$ptsLabel';
    }).join('\n');
    final signOff = (student?.name.isNotEmpty ?? false) ? student!.name : '';
    return 'Hi $salutation,\n\n'
        "I'm reaching out about the following in ${group.course.name}:\n\n"
        '$lines\n\n'
        '\n\n'
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
}

class _CheckInRow extends ConsumerWidget {
  const _CheckInRow({required this.item, required this.course});
  final MergedItem item;
  final MergedCourse course;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: colors.cardSubtle,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textStrong,
                  ),
                ),
                if (item.date != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'due ${item.date}',
                      style:
                          TextStyle(fontSize: 11, color: colors.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Asked already',
            icon: const Icon(Icons.check, size: 18),
            color: colors.textSecondary,
            visualDensity: VisualDensity.compact,
            onPressed: () => _unflag(ref),
          ),
        ],
      ),
    );
  }

  /// Clears the flag by deleting the marker comment. A marker that's collected
  /// replies is left in place — dropping it would take the thread with it.
  Future<void> _unflag(WidgetRef ref) async {
    final threads = ref.read(selectedStudentProvider).value?.comments[item.key] ??
        const <CommentThread>[];
    final marker = threads
        .where((t) => t.text.trim() == kTeacherCheckInNote && t.replies.isEmpty)
        .firstOrNull;
    if (marker == null) return;
    await ref
        .read(assignmentActionsProvider)
        .deleteComment(key: item.key, commentId: marker.id);
  }
}

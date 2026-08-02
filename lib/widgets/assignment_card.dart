import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:assignment_tracker_app/domain/merged.dart';
import 'package:assignment_tracker_app/domain/priority.dart';
import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:assignment_tracker_app/state/student_providers.dart';
import 'package:assignment_tracker_app/theme/app_theme.dart';
import 'assignment_actions_sheet.dart';
import 'status_badges.dart';

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
    final colors = AppColors.of(context);
    final student = ref.watch(selectedStudentProvider).value;
    final thresholds = student?.scoreThresholds ?? const <String, int>{};
    final statusByKey = student?.assignmentStatus ?? const <String, LocalStatus>{};
    final actionable = isActionable(item, course.name, thresholds);
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
        color: colors.card,
        border: Border.all(color: colors.border),
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
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.textStrong)),
            ],
          ),
          const SizedBox(height: 4),
          Text('due ${item.date ?? '?'}',
              style: TextStyle(fontSize: 12, color: colors.textSecondary)),
          if (statusBadgesFor(context, item, statusByKey).isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
                spacing: 4,
                runSpacing: 4,
                children: statusBadgesFor(context, item, statusByKey)),
          ],
          if (actionable) ...[
            const SizedBox(height: 10),
            AssignmentActionsSheet(item: item, course: course),
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
}

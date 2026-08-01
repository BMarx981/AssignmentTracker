import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/merged.dart';
import '../domain/priority.dart';
import '../models/api_models.dart';
import '../state/student_providers.dart';
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

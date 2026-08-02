import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:assignment_tracker_app/domain/merged.dart';
import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:assignment_tracker_app/state/assignment_actions.dart';
import 'package:assignment_tracker_app/theme/app_theme.dart';
import 'assignment_actions_sheet.dart';
import 'status_badges.dart';

/// One row of the home-screen catch-up list. Minimal by design:
/// assignment name + one badge + tap-to-act.
///
/// Swiping is the fast path — right marks the assignment turned in, left opens
/// the full action sheet. The sheet is the escalation, not the only route, so
/// clearing a list of things you actually did doesn't cost a modal each time.
class CatchUpRow extends ConsumerWidget {
  final MergedItem item;
  final MergedCourse course;
  final Map<String, LocalStatus> statusByKey;

  const CatchUpRow({
    super.key,
    required this.item,
    required this.course,
    required this.statusByKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final badge = primaryBadgeFor(context, item, statusByKey);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Dismissible(
        key: ValueKey('catch-up-${item.key}'),
        // Neither direction actually removes the widget — `confirmDismiss`
        // always returns false and the row springs back. Marking it done
        // re-reads the data, which is what drops it from the list.
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            await _markDone(context, ref);
          } else {
            await showAssignmentActionsSheet(
              context,
              item: item,
              course: course,
            );
          }
          return false;
        },
        dismissThresholds: const {
          DismissDirection.startToEnd: 0.35,
          DismissDirection.endToStart: 0.35,
        },
        background: _SwipeBackground(
          alignment: Alignment.centerLeft,
          icon: Icons.check_circle_outline,
          label: 'Turned it in',
          style: colors.success,
        ),
        secondaryBackground: _SwipeBackground(
          alignment: Alignment.centerRight,
          icon: Icons.tune,
          label: 'Options',
          style: colors.actionChip,
        ),
        child: InkWell(
          onTap: () => showAssignmentActionsSheet(
            context,
            item: item,
            course: course,
          ),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: BoxDecoration(
              color: colors.card,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textStrong,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  badge,
                ],
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 18, color: colors.chevron),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _markDone(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final actions = ref.read(assignmentActionsProvider);
    // Snapshot first: undo has to put back whatever claim was there before,
    // not just clear it, or a swipe would silently eat an existing plan date.
    final previous = statusByKey[item.key];

    await actions.markSubmittedNow(
      key: item.key,
      assignmentName: item.name,
      courseName: course.name,
    );

    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Marked "${item.name}" as turned in.'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _restore(actions, previous),
          ),
        ),
      );
  }

  Future<void> _restore(AssignmentActions actions, LocalStatus? previous) {
    if (previous == null) return actions.clear(item.key);
    return actions.setStatus(
      key: item.key,
      status: previous.status,
      assignmentName: previous.assignmentName,
      courseName: previous.courseName,
      plannedDate: _parseYmd(previous.plannedDate),
      submittedDate: _parseYmd(previous.submittedDate),
    );
  }

  static DateTime? _parseYmd(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value.length == 10 ? '${value}T00:00:00' : value);
  }
}

/// The colored panel revealed behind the row while swiping.
class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.icon,
    required this.label,
    required this.style,
  });

  final Alignment alignment;
  final IconData icon;
  final String label;
  final BadgeStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: style.foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: style.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

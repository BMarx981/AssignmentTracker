import 'package:flutter/material.dart';

import 'package:assignment_tracker_app/domain/merged.dart';
import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:assignment_tracker_app/theme/app_theme.dart';
import 'assignment_actions_sheet.dart';
import 'status_badges.dart';

/// One row of the home-screen catch-up list. Minimal by design:
/// assignment name + one badge + tap-to-act.
class CatchUpRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final badge = primaryBadgeFor(context, item, statusByKey);
    return InkWell(
      onTap: () => showAssignmentActionsSheet(
        context,
        item: item,
        course: course,
      ),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
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
    );
  }
}

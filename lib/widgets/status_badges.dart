import 'package:flutter/material.dart';

import '../domain/merged.dart';
import '../domain/priority.dart';
import '../models/api_models.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';

/// A small colored chip that mirrors the dashboard.html `.badge` element.
class StatusBadge extends StatelessWidget {
  final String label;
  final BadgeStyle style;
  const StatusBadge({super.key, required this.label, required this.style});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: style.foreground,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Returns the list of badges for an assignment — direct port of statusBadges().
List<Widget> statusBadgesFor(
  BuildContext context,
  MergedItem item,
  Map<String, LocalStatus> statusByKey, {
  DateTime? today,
}) {
  final c = AppColors.of(context);
  final out = <Widget>[];
  final now = today ?? DateTime.now();
  final todayMidnight = DateTime(now.year, now.month, now.day);
  final tomorrow = todayMidnight.add(const Duration(days: 1));
  final dayAfter = todayMidnight.add(const Duration(days: 2));

  if (item.status == 'missing') {
    DateTime? due;
    if (item.date != null && item.date!.isNotEmpty) {
      due = DateTime.tryParse(
          item.date!.length == 10 ? '${item.date}T00:00:00' : item.date!);
    }
    if (due != null && !due.isBefore(todayMidnight) && due.isBefore(tomorrow)) {
      out.add(StatusBadge(label: 'due today', style: c.dueSoon));
    } else if (due != null &&
        !due.isBefore(tomorrow) &&
        due.isBefore(dayAfter)) {
      out.add(StatusBadge(label: 'due tomorrow', style: c.dueSoon));
    } else if (due != null && due.isAfter(todayMidnight)) {
      out.add(StatusBadge(label: 'upcoming', style: c.success));
    } else {
      out.add(StatusBadge(label: 'missing', style: c.danger));
    }
  }
  if (item.status == 'half_credit_missing') {
    out.add(StatusBadge(label: '50% credit', style: c.halfCredit));
  }
  if (item.status == 'zero_graded') {
    out.add(StatusBadge(label: 'zero-graded', style: c.zeroGraded));
  }
  if (item.status == 'not_graded') {
    out.add(StatusBadge(label: 'not yet graded', style: c.info));
  }
  if (item.canvasStatus == 'submitted_pending') {
    out.add(StatusBadge(label: 'submitted · awaiting grade', style: c.info));
  }
  if (item.inClass) {
    out.add(StatusBadge(label: 'likely in-class', style: c.inClass));
  }
  if (item.source == 'synergy') {
    out.add(StatusBadge(label: 'Synergy', style: c.synergy));
  } else if (item.source == 'canvas') {
    out.add(StatusBadge(label: 'Canvas only', style: c.canvas));
  } else if (item.source == 'both') {
    out.add(StatusBadge(label: 'Synergy+Canvas', style: c.synergy));
  }
  final ls = getLocalStatus(item, statusByKey);
  if (ls != null) {
    if (ls.status == 'planned') {
      final d = fmtPlanDate(ls.plannedDate);
      out.add(StatusBadge(
          label: '\u{1F4C5} plan: ${d.isEmpty ? 'date' : d}',
          style: c.success));
    } else {
      final label = ls.status == 'submitted_pending_feedback'
          ? 'submitted · awaiting grade'
          : 'complete · pending submission';
      final isSpend = ls.status == 'submitted_pending_feedback';
      final dateStr =
          ls.submittedDate != null ? fmtPlanDate(ls.submittedDate) : '';
      out.add(StatusBadge(
        label: dateStr.isEmpty ? label : '$label · $dateStr',
        style: isSpend ? c.submitted : c.success,
      ));
    }
  }
  return out;
}

/// One-badge picker for the home/catch-up list. Order of preference:
/// 1. Local claim (planned / complete-pending / submitted-pending)
/// 2. Due phrase for missing items (due today / due tomorrow / was due X / due in N days)
/// 3. zero-graded or 50% credit for the recovery cases
///
/// Returns null if none apply.
StatusBadge? primaryBadgeFor(
  BuildContext context,
  MergedItem item,
  Map<String, LocalStatus> statusByKey, {
  DateTime? today,
}) {
  final c = AppColors.of(context);
  final ls = getLocalStatus(item, statusByKey);
  if (ls != null) {
    if (ls.status == 'planned') {
      final d = fmtPlanDate(ls.plannedDate);
      return StatusBadge(
        label: '\u{1F4C5} plan: ${d.isEmpty ? 'date' : d}',
        style: c.success,
      );
    }
    final isSpend = ls.status == 'submitted_pending_feedback';
    return StatusBadge(
      label: isSpend ? 'submitted · awaiting' : 'done · pending submit',
      style: isSpend ? c.submitted : c.success,
    );
  }

  final now = today ?? DateTime.now();
  final todayMidnight = DateTime(now.year, now.month, now.day);

  if (item.status == 'missing') {
    DateTime? due;
    if (item.date != null && item.date!.isNotEmpty) {
      due = DateTime.tryParse(
          item.date!.length == 10 ? '${item.date}T00:00:00' : item.date!);
    }
    if (due == null) {
      return StatusBadge(label: 'missing', style: c.danger);
    }
    final dueMidnight = DateTime(due.year, due.month, due.day);
    final days = dueMidnight.difference(todayMidnight).inDays;
    if (days < 0) {
      // Overdue. Show "was due Mon 6/9" if within a week, else "missing".
      if (days >= -7) {
        return StatusBadge(
          label: 'was due ${fmtPlanDate(item.date)}',
          style: c.danger,
        );
      }
      return StatusBadge(label: 'missing', style: c.danger);
    }
    if (days == 0) {
      return StatusBadge(label: 'due today', style: c.dueSoon);
    }
    if (days == 1) {
      return StatusBadge(label: 'due tomorrow', style: c.dueSoon);
    }
    return StatusBadge(label: 'due in $days days', style: c.success);
  }
  if (item.status == 'half_credit_missing') {
    return StatusBadge(label: '50% credit', style: c.halfCredit);
  }
  if (item.status == 'zero_graded') {
    return StatusBadge(label: 'zero-graded', style: c.zeroGraded);
  }
  return null;
}

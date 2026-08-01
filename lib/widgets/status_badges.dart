import 'package:flutter/material.dart';

import '../domain/merged.dart';
import '../domain/priority.dart';
import '../models/api_models.dart';
import '../util/format.dart';

/// A small colored chip that mirrors the dashboard.html `.badge` element.
class StatusBadge extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  const StatusBadge({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// CSS color palette from dashboard.html, mapped 1:1.
const _bgMissing = Color(0xFFFDE2E2);
const _fgMissing = Color(0xFF8A1A1A);
const _bgUpcoming = Color(0xFFD1FAE5);
const _fgUpcoming = Color(0xFF065F46);
const _bgDueSoon = Color(0xFFFFF3CD);
const _fgDueSoon = Color(0xFF7C4A00);
const _bgZero = Color(0xFFFFE9C2);
const _fgZero = Color(0xFF7C4A00);
const _bgPending = Color(0xFFE1ECFF);
const _fgPending = Color(0xFF1B3F88);
const _bgHalf = Color(0xFFFFEED1);
const _fgHalf = Color(0xFF6E4B00);
const _bgIcl = Color(0xFFECE4FF);
const _fgIcl = Color(0xFF4B2A86);
const _bgSyn = Color(0xFFE2F5E6);
const _fgSyn = Color(0xFF1B5E29);
const _bgCanvas = Color(0xFFE9EAFF);
const _fgCanvas = Color(0xFF2A2D83);
const _bgCpend = Color(0xFFD1FAE5);
const _fgCpend = Color(0xFF065F46);
const _bgSpend = Color(0xFFDBEAFE);
const _fgSpend = Color(0xFF1E40AF);

/// Returns the list of badges for an assignment — direct port of statusBadges().
List<Widget> statusBadgesFor(
  MergedItem item,
  Map<String, LocalStatus> statusByKey, {
  DateTime? today,
}) {
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
      out.add(const StatusBadge(
          label: 'due today',
          background: _bgDueSoon,
          foreground: _fgDueSoon));
    } else if (due != null &&
        !due.isBefore(tomorrow) &&
        due.isBefore(dayAfter)) {
      out.add(const StatusBadge(
          label: 'due tomorrow',
          background: _bgDueSoon,
          foreground: _fgDueSoon));
    } else if (due != null && due.isAfter(todayMidnight)) {
      out.add(const StatusBadge(
          label: 'upcoming',
          background: _bgUpcoming,
          foreground: _fgUpcoming));
    } else {
      out.add(const StatusBadge(
          label: 'missing',
          background: _bgMissing,
          foreground: _fgMissing));
    }
  }
  if (item.status == 'half_credit_missing') {
    out.add(const StatusBadge(
        label: '50% credit', background: _bgHalf, foreground: _fgHalf));
  }
  if (item.status == 'zero_graded') {
    out.add(const StatusBadge(
        label: 'zero-graded', background: _bgZero, foreground: _fgZero));
  }
  if (item.status == 'not_graded') {
    out.add(const StatusBadge(
        label: 'not yet graded',
        background: _bgPending,
        foreground: _fgPending));
  }
  if (item.canvasStatus == 'submitted_pending') {
    out.add(const StatusBadge(
        label: 'submitted · awaiting grade',
        background: _bgPending,
        foreground: _fgPending));
  }
  if (item.inClass) {
    out.add(const StatusBadge(
        label: 'likely in-class', background: _bgIcl, foreground: _fgIcl));
  }
  if (item.source == 'synergy') {
    out.add(const StatusBadge(
        label: 'Synergy', background: _bgSyn, foreground: _fgSyn));
  } else if (item.source == 'canvas') {
    out.add(const StatusBadge(
        label: 'Canvas only',
        background: _bgCanvas,
        foreground: _fgCanvas));
  } else if (item.source == 'both') {
    out.add(const StatusBadge(
        label: 'Synergy+Canvas',
        background: _bgSyn,
        foreground: _fgSyn));
  }
  final ls = getLocalStatus(item, statusByKey);
  if (ls != null) {
    if (ls.status == 'planned') {
      final d = fmtPlanDate(ls.plannedDate);
      out.add(StatusBadge(
          label: '📅 plan: ${d.isEmpty ? 'date' : d}',
          background: _bgCpend,
          foreground: _fgCpend));
    } else {
      final label = ls.status == 'submitted_pending_feedback'
          ? 'submitted · awaiting grade'
          : 'complete · pending submission';
      final isSpend = ls.status == 'submitted_pending_feedback';
      final dateStr =
          ls.submittedDate != null ? fmtPlanDate(ls.submittedDate) : '';
      out.add(StatusBadge(
        label: dateStr.isEmpty ? label : '$label · $dateStr',
        background: isSpend ? _bgSpend : _bgCpend,
        foreground: isSpend ? _fgSpend : _fgCpend,
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
  MergedItem item,
  Map<String, LocalStatus> statusByKey, {
  DateTime? today,
}) {
  final ls = getLocalStatus(item, statusByKey);
  if (ls != null) {
    if (ls.status == 'planned') {
      final d = fmtPlanDate(ls.plannedDate);
      return StatusBadge(
        label: '📅 plan: ${d.isEmpty ? 'date' : d}',
        background: _bgCpend,
        foreground: _fgCpend,
      );
    }
    final isSpend = ls.status == 'submitted_pending_feedback';
    return StatusBadge(
      label: isSpend ? 'submitted · awaiting' : 'done · pending submit',
      background: isSpend ? _bgSpend : _bgCpend,
      foreground: isSpend ? _fgSpend : _fgCpend,
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
      return const StatusBadge(
          label: 'missing', background: _bgMissing, foreground: _fgMissing);
    }
    final dueMidnight = DateTime(due.year, due.month, due.day);
    final days = dueMidnight.difference(todayMidnight).inDays;
    if (days < 0) {
      // Overdue. Show "was due Mon 6/9" if within a week, else "missing".
      if (days >= -7) {
        return StatusBadge(
          label: 'was due ${fmtPlanDate(item.date)}',
          background: _bgMissing,
          foreground: _fgMissing,
        );
      }
      return const StatusBadge(
          label: 'missing', background: _bgMissing, foreground: _fgMissing);
    }
    if (days == 0) {
      return const StatusBadge(
          label: 'due today', background: _bgDueSoon, foreground: _fgDueSoon);
    }
    if (days == 1) {
      return const StatusBadge(
          label: 'due tomorrow',
          background: _bgDueSoon,
          foreground: _fgDueSoon);
    }
    return StatusBadge(
      label: 'due in $days days',
      background: _bgUpcoming,
      foreground: _fgUpcoming,
    );
  }
  if (item.status == 'half_credit_missing') {
    return const StatusBadge(
        label: '50% credit', background: _bgHalf, foreground: _fgHalf);
  }
  if (item.status == 'zero_graded') {
    return const StatusBadge(
        label: 'zero-graded', background: _bgZero, foreground: _fgZero);
  }
  return null;
}

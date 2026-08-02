import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:assignment_tracker_app/domain/assignment_situation.dart';
import 'package:assignment_tracker_app/domain/merged.dart';
import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:assignment_tracker_app/state/assignment_actions.dart';
import 'package:assignment_tracker_app/state/student_providers.dart';
import 'package:assignment_tracker_app/theme/app_theme.dart';
import 'package:assignment_tracker_app/util/format.dart';

/// The per-assignment action panel, shared by the catch-up row's bottom sheet
/// and the course-detail assignment card.
///
/// Laid out as three disclosure groups ordered by how often they're needed,
/// rather than a flat chip row. Everything in the catch-up list is missing or
/// zero-graded by construction, so "I still owe this, when will I do it?" is
/// the overwhelmingly common answer — that group is expanded at rest so
/// planning costs a single tap. The two rarer groups (the student disagrees
/// with the gradebook) stay collapsed behind one line each.
///
/// If the student already answered for this assignment, the panel opens on a
/// current-state header with a Change button instead of the fresh chooser.
class AssignmentActionsSheet extends ConsumerStatefulWidget {
  const AssignmentActionsSheet({
    super.key,
    required this.item,
    required this.course,
    this.onDone,
  });

  final MergedItem item;
  final MergedCourse course;

  /// Invoked after a terminal action so the host can dismiss itself. Null when
  /// the panel is embedded inline, where there's no sheet to close.
  final VoidCallback? onDone;

  @override
  ConsumerState<AssignmentActionsSheet> createState() =>
      _AssignmentActionsSheetState();
}

class _AssignmentActionsSheetState
    extends ConsumerState<AssignmentActionsSheet> {
  /// Which group the student explicitly toggled. Null until they touch one,
  /// at which point [_dirty] makes it win over the derived default.
  SheetGroup? _expanded;
  bool _dirty = false;

  /// Set by "Change" — drops the current-state header and shows the chooser.
  bool _changing = false;

  @override
  Widget build(BuildContext context) {
    final student = ref.watch(selectedStudentProvider).value;
    final situation = resolveSituation(
      item: widget.item,
      statusByKey: student?.assignmentStatus ?? const <String, LocalStatus>{},
      comments: student?.comments ?? const <String, List<CommentThread>>{},
    );
    final showHeader = situation.isRecorded && !_changing;
    final expanded = _resolveExpanded(situation, showHeader);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHeader) ...[
          _CurrentStateHeader(
            situation: situation,
            onChange: () => setState(() {
              _changing = true;
              _dirty = false;
              _expanded = null;
            }),
            onClear: situation.status == null
                ? null
                : () => _run(
                      () => ref
                          .read(assignmentActionsProvider)
                          .clear(widget.item.key),
                    ),
          ),
          const SizedBox(height: 14),
        ],
        _Group(
          group: SheetGroup.plan,
          label: 'Plan it',
          expanded: expanded == SheetGroup.plan,
          onTap: () => _toggle(SheetGroup.plan, expanded),
          child: _planChips(situation),
        ),
        _Group(
          group: SheetGroup.alreadyDid,
          label: 'I already did it',
          expanded: expanded == SheetGroup.alreadyDid,
          onTap: () => _toggle(SheetGroup.alreadyDid, expanded),
          child: _doneChips(situation),
        ),
        _Group(
          group: SheetGroup.somethingsOff,
          label: "Something's off about this",
          secondary: true,
          expanded: expanded == SheetGroup.somethingsOff,
          onTap: () => _toggle(SheetGroup.somethingsOff, expanded),
          child: _flagRows(situation),
        ),
      ],
    );
  }

  /// The default is "plan expanded" for a fresh assignment; for one the
  /// student already answered, open the group their answer came from.
  SheetGroup? _resolveExpanded(AssignmentSituation situation, bool showHeader) {
    if (_dirty) return _expanded;
    if (showHeader) return situation.group;
    return SheetGroup.plan;
  }

  void _toggle(SheetGroup group, SheetGroup? current) {
    setState(() {
      _dirty = true;
      _expanded = current == group ? null : group;
    });
  }

  /// Runs a mutation, then closes the host sheet. Used for the answers that
  /// finish the interaction, so the student lands straight back in the list.
  Future<void> _run(Future<void> Function() op) async {
    await op();
    if (!mounted) return;
    widget.onDone?.call();
  }

  // ---------- plan ----------

  Widget _planChips(AssignmentSituation situation) {
    final colors = AppColors.of(context);
    final planned = situation.status?.status == 'planned'
        ? situation.status?.plannedDate
        : null;
    final now = DateTime.now();
    final options = <(String, DateTime)>[
      ('Tonight', now),
      ('Tomorrow', now.add(const Duration(days: 1))),
      ('Weekend', _comingWeekend(now)),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (label, date) in options)
          _Pill(
            label: label,
            selected: planned == ymd(date),
            style: colors.actionChip,
            onTap: () => _plan(date),
          ),
        _Pill(
          label: planned != null && !_isPreset(planned, options)
              ? fmtPlanDate(planned)
              : 'Pick a date…',
          selected: planned != null && !_isPreset(planned, options),
          style: colors.neutralChip,
          onTap: _pickDate,
        ),
      ],
    );
  }

  bool _isPreset(String planned, List<(String, DateTime)> options) =>
      options.any((o) => ymd(o.$2) == planned);

  /// The coming Saturday, or today if it's already the weekend.
  static DateTime _comingWeekend(DateTime now) {
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return now;
    }
    return now.add(Duration(days: DateTime.saturday - now.weekday));
  }

  Future<void> _plan(DateTime date) => _run(
        () => ref.read(assignmentActionsProvider).setStatus(
              key: widget.item.key,
              status: 'planned',
              assignmentName: widget.item.name,
              courseName: widget.course.name,
              plannedDate: date,
            ),
      );

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    await _plan(picked);
  }

  // ---------- already did it ----------

  Widget _doneChips(AssignmentSituation situation) {
    final colors = AppColors.of(context);
    final state = situation.state;
    final submitted = state == AssignmentState.submitted;
    final donePending = state == AssignmentState.doneNotSubmitted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Pill(
              label: 'Turned it in',
              selected: submitted,
              style: colors.actionChip,
              onTap: () => _run(
                () => ref.read(assignmentActionsProvider).markSubmittedNow(
                      key: widget.item.key,
                      assignmentName: widget.item.name,
                      courseName: widget.course.name,
                    ),
              ),
            ),
            _Pill(
              label: 'Done, not turned in yet',
              selected: donePending,
              style: colors.actionChip,
              onTap: () => _run(
                () => ref.read(assignmentActionsProvider).setStatus(
                      key: widget.item.key,
                      status: 'complete_pending_submission',
                      assignmentName: widget.item.name,
                      courseName: widget.course.name,
                    ),
              ),
            ),
          ],
        ),
        // The nudge from "done" to "turned in" — the whole point of tracking
        // complete-pending separately is to come back and finish it.
        if (donePending)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Turned it in since then? Tap "Turned it in".',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.of(context).textSecondary,
              ),
            ),
          ),
      ],
    );
  }

  // ---------- something's off ----------

  Widget _flagRows(AssignmentSituation situation) {
    return Column(
      children: [
        _FlagRow(
          label: 'Thought I handed it in',
          subtitle: 'Marks that you believed this was already turned in.',
          selected: situation.thoughtHandedIn,
          // Composes with the teacher reminder below, so setting it leaves the
          // panel open rather than dismissing.
          onTap: () => _toggleFlag(kThoughtHandedInNote,
              set: !situation.thoughtHandedIn, dismiss: false),
        ),
        _FlagRow(
          label: 'Remind me to ask teacher',
          subtitle: 'Adds this to your teacher check-in list.',
          selected: situation.teacherCheckIn,
          onTap: () => _toggleFlag(kTeacherCheckInNote,
              set: !situation.teacherCheckIn, dismiss: false),
        ),
        _FlagRow(
          label: 'Not sure',
          subtitle: "Flags this for follow-up without picking a status.",
          selected: situation.unsure,
          onTap: () => _toggleFlag(kNotSureNote,
              set: !situation.unsure, dismiss: true),
        ),
      ],
    );
  }

  /// Flags are stored as comment threads, so setting one posts the marker and
  /// clearing one deletes it. A marker that's picked up replies is left alone —
  /// deleting the thread would take the conversation with it.
  Future<void> _toggleFlag(
    String note, {
    required bool set,
    required bool dismiss,
  }) async {
    final actions = ref.read(assignmentActionsProvider);
    if (set) {
      if (dismiss) {
        await _run(() => actions.postComment(key: widget.item.key, text: note));
      } else {
        await actions.postComment(key: widget.item.key, text: note);
      }
      return;
    }
    final threads = ref.read(selectedStudentProvider).value?.comments[
            widget.item.key] ??
        const <CommentThread>[];
    final marker = threads
        .where((t) => t.text.trim() == note && t.replies.isEmpty)
        .firstOrNull;
    if (marker == null) return;
    await actions.deleteComment(key: widget.item.key, commentId: marker.id);
  }
}

/// "Here's where this stands" + the way back to the chooser.
class _CurrentStateHeader extends StatelessWidget {
  const _CurrentStateHeader({
    required this.situation,
    required this.onChange,
    this.onClear,
  });

  final AssignmentSituation situation;
  final VoidCallback onChange;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    // A status claim reads as settled; a bare flag reads as unresolved.
    final style =
        situation.status != null ? colors.success : colors.neutralChip;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            situation.status != null
                ? Icons.check_circle_outline
                : Icons.flag_outlined,
            size: 18,
            color: style.foreground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              situation.summary,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: style.foreground,
              ),
            ),
          ),
          if (onClear != null)
            TextButton(
              onPressed: onClear,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: colors.textSecondary,
              ),
              child: const Text('Clear', style: TextStyle(fontSize: 13)),
            ),
          TextButton(
            onPressed: onChange,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: style.foreground,
            ),
            child: const Text(
              'Change',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// One disclosure group: a tappable label row plus its body when expanded.
class _Group extends StatelessWidget {
  const _Group({
    required this.group,
    required this.label,
    required this.expanded,
    required this.onTap,
    required this.child,
    this.secondary = false,
  });

  final SheetGroup group;
  final String label;
  final bool expanded;
  final VoidCallback onTap;
  final Widget child;

  /// Renders muted and smaller — used for the rare "gradebook is wrong" group
  /// so it reads as an escape hatch rather than a peer of the other two.
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            // Tall enough to be a comfortable thumb target.
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    key: Key('group-label-${group.name}'),
                    style: TextStyle(
                      fontSize: secondary ? 13 : 15,
                      fontWeight: secondary ? FontWeight.w600 : FontWeight.w700,
                      color:
                          secondary ? colors.textSecondary : colors.textStrong,
                    ),
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: secondary ? colors.textFaint : colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 12),
            child: SizedBox(width: double.infinity, child: child),
          ),
      ],
    );
  }
}

/// A rounded action pill. Selected pills flip to the success palette.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.style,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final BadgeStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final effective = selected ? colors.success : style;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: effective.background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check, size: 15, color: effective.foreground),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: effective.foreground,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A full-width flag row. Wider than a pill because each one carries a line
/// explaining what it actually does.
class _FlagRow extends StatelessWidget {
  const _FlagRow({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? colors.success.background : colors.cardSubtle,
          border: Border.all(
            color: selected ? colors.success.foreground : colors.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? colors.success.foreground
                          : colors.textStrong,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: selected
                          ? colors.success.foreground
                          : colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check, size: 17, color: colors.success.foreground),
          ],
        ),
      ),
    );
  }
}

/// Opens the action panel as a modal bottom sheet. Terminal actions inside it
/// pop the sheet themselves.
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
        child: SingleChildScrollView(
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
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                course.name,
                style: TextStyle(
                    fontSize: 12, color: AppColors.of(ctx).textSecondary),
              ),
              const SizedBox(height: 12),
              AssignmentActionsSheet(
                item: item,
                course: course,
                onDone: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      );
    },
  );
}

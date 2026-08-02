import 'package:flutter/material.dart';

import 'package:assignment_tracker_app/domain/merged.dart';
import 'package:assignment_tracker_app/domain/priority.dart';
import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:assignment_tracker_app/theme/app_theme.dart';
import 'package:assignment_tracker_app/util/format.dart';

/// Color band for the big percent text + left-edge accent.
Color gradeBandColor(BuildContext context, String band) {
  final c = AppColors.of(context);
  switch (band) {
    case 'bad':
      return c.gradeBad;
    case 'warn':
      return c.gradeWarn;
    case 'ok':
      return c.gradeOk;
    default:
      return c.gradeNone;
  }
}

class CourseSummaryCard extends StatefulWidget {
  final MergedCourse course;
  final GradeBands bands;
  final Map<String, LocalStatus> statusByKey;
  final DateRange range;
  final VoidCallback? onTap;

  const CourseSummaryCard({
    super.key,
    required this.course,
    required this.bands,
    required this.statusByKey,
    required this.range,
    this.onTap,
  });

  @override
  State<CourseSummaryCard> createState() => _CourseSummaryCardState();
}

class _CourseSummaryCardState extends State<CourseSummaryCard> {
  bool _gradesHidden = true;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final course = widget.course;

    // One grade number, picked in priority order.
    final double? p;
    final String gradeSource;
    if (course.policyHalfCredit &&
        course.synergyAltHalfCreditPercent != null) {
      p = course.synergyAltHalfCreditPercent;
      gradeSource = 'Synergy · history rule';
    } else if (course.synergyPercent != null) {
      p = course.synergyPercent;
      gradeSource =
          course.synergyPercentIsComputed ? 'Synergy (est.)' : 'Synergy';
    } else if (course.canvasAvgWithMissing != null) {
      p = course.canvasAvgWithMissing;
      gradeSource = 'Canvas worst-case';
    } else {
      p = null;
      gradeSource = 'No grade yet';
    }
    final band = courseClass(p, widget.bands);
    final accent = gradeBandColor(context, band);

    // Two-pill summary: things-to-catch-up vs. already-pending.
    final synMiss = course.items
        .where((it) => it.source != 'canvas')
        .where((it) =>
            widget.range.contains(it.date) && it.status == 'missing')
        .length;
    final cMiss = course.items
        .where((it) => it.source != 'synergy')
        .where((it) =>
            widget.range.contains(it.date) && it.canvasStatus == 'missing')
        .length;
    final cZero = course.items
        .where((it) =>
            widget.range.contains(it.date) && it.status == 'zero_graded')
        .length;
    final toCatchUp = synMiss + cMiss + cZero;

    final localEntries = widget.statusByKey.values
        .where((e) => e.courseName == course.name);
    final nComplete = localEntries
        .where((e) => e.status == 'complete_pending_submission')
        .length;
    final nSubmitted = localEntries
        .where((e) => e.status == 'submitted_pending_feedback')
        .length;
    final nPending = nComplete + nSubmitted;

    final pills = <Widget>[];
    if (toCatchUp > 0) {
      pills.add(_pill(context, '$toCatchUp to catch up', warn: true));
    }
    if (nPending > 0) {
      pills.add(_pill(context, '$nPending pending', style: colors.success));
    }

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: colors.card,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    course.name,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.25),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () =>
                      setState(() => _gradesHidden = !_gradesHidden),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      _gradesHidden ? Icons.visibility_off : Icons.visibility,
                      size: 16,
                      color: colors.iconMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _gradeRow(
              colors: colors,
              source: gradeSource,
              percent: p,
              letter: course.synergyLetter,
              accent: accent,
            ),
            if (pills.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 4, runSpacing: 4, children: pills),
            ],
          ],
        ),
      ),
    );
  }

  Widget _gradeRow({
    required AppColors colors,
    required String source,
    required double? percent,
    required String? letter,
    required Color accent,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(source,
                style:
                    TextStyle(fontSize: 11, color: colors.textFaint)),
          ),
          if (!_gradesHidden) ...[
            if (letter != null && letter.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(letter,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            Text(
              pctText(percent),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: accent,
                height: 1,
              ),
            ),
          ] else
            Text(
              '•••',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: colors.gradeHidden,
                height: 1,
              ),
            ),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, String text,
      {bool warn = false, BadgeStyle? style}) {
    final colors = AppColors.of(context);
    final s = style ?? (warn ? colors.zeroGraded : colors.neutralPill);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: s.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
            color: s.foreground, fontSize: 10.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../domain/merged.dart';
import '../domain/priority.dart';
import '../models/api_models.dart';
import '../util/format.dart';

/// Color band for the big percent text + left-edge accent.
Color gradeBandColor(String band) {
  switch (band) {
    case 'bad':
      return const Color(0xFFB71C1C);
    case 'warn':
      return const Color(0xFFC77700);
    case 'ok':
      return const Color(0xFF1F7A3A);
    default:
      return const Color(0xFF999999);
  }
}

class CourseSummaryCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final p = course.synergyPercent ?? course.canvasAvgWithMissing;
    final band = courseClass(p, bands);
    final accent = gradeBandColor(band);

    final pills = <Widget>[];
    final synMiss = course.items
        .where((it) => it.source != 'canvas')
        .where((it) => range.contains(it.date) && it.status == 'missing')
        .length;
    if (course.synergyPercent != null || course.items.any((i) => i.source == 'synergy' || i.source == 'both')) {
      pills.add(_pill('$synMiss Syn-missing', warn: synMiss > 0, bad: synMiss > 0));
    }
    final cMiss = course.items
        .where((it) => it.source != 'synergy')
        .where((it) => range.contains(it.date) && it.canvasStatus == 'missing')
        .length;
    final cZero = course.items
        .where((it) => range.contains(it.date) && it.status == 'zero_graded')
        .length;
    if (cMiss > 0) pills.add(_pill('$cMiss Canvas-missing', warn: true));
    if (cZero > 0) pills.add(_pill('$cZero zero-graded', warn: true));

    final localEntries = statusByKey.values.where((e) => e.courseName == course.name);
    final nComplete =
        localEntries.where((e) => e.status == 'complete_pending_submission').length;
    final nSubmitted =
        localEntries.where((e) => e.status == 'submitted_pending_feedback').length;
    if (nComplete > 0) {
      pills.add(_pill('$nComplete complete · pending submit',
          background: const Color(0xFFD1FAE5), foreground: const Color(0xFF065F46)));
    }
    if (nSubmitted > 0) {
      pills.add(_pill('$nSubmitted submitted · awaiting grade',
          background: const Color(0xFFDBEAFE), foreground: const Color(0xFF1E40AF)));
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE3E3E3)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              course.name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.25),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (course.teacher != null && course.teacher!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(course.teacher!,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF888888))),
              ),
            const SizedBox(height: 8),
            _gradeRow(
              label: 'Synergy${course.synergyPercentIsComputed ? ' (est.)' : ''}',
              percent: course.synergyPercent,
              letter: course.synergyLetter,
              accent: accent,
              big: true,
            ),
            if (course.policyHalfCredit && course.synergyAltHalfCreditPercent != null)
              _row('If missing = 50%', pctText(course.synergyAltHalfCreditPercent),
                  bold: true),
            if (course.canvasAvgWithMissing != null)
              _row('Canvas worst-case', pctText(course.canvasAvgWithMissing),
                  bold: true),
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
    required String label,
    required double? percent,
    required String? letter,
    required Color accent,
    bool big = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF555555))),
          ),
          if (letter != null && letter.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(letter,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          Text(
            pctText(percent),
            style: TextStyle(
              fontSize: big ? 24 : 14,
              fontWeight: FontWeight.w700,
              color: accent,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF555555)))),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _pill(String text, {bool warn = false, bool bad = false, Color? background, Color? foreground}) {
    Color bg;
    Color fg;
    if (background != null && foreground != null) {
      bg = background;
      fg = foreground;
    } else if (bad) {
      bg = const Color(0xFFFDE2E2);
      fg = const Color(0xFF8A1A1A);
    } else if (warn) {
      bg = const Color(0xFFFFE9C2);
      fg = const Color(0xFF7C4A00);
    } else {
      bg = const Color(0xFFEEEEEE);
      fg = const Color(0xFF333333);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
            color: fg, fontSize: 10.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

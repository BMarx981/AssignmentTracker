import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:assignment_tracker_app/domain/merged.dart';
import 'package:assignment_tracker_app/domain/priority.dart';
import 'package:assignment_tracker_app/router.dart';
import 'package:assignment_tracker_app/state/data_providers.dart';
import 'package:assignment_tracker_app/state/prefs_providers.dart';
import 'package:assignment_tracker_app/state/priority_providers.dart';
import 'package:assignment_tracker_app/state/student_providers.dart';
import 'package:assignment_tracker_app/theme/app_theme.dart';
import 'package:assignment_tracker_app/util/format.dart';
import 'package:assignment_tracker_app/widgets/assignment_card.dart';
import 'package:assignment_tracker_app/widgets/comments_panel.dart';
import 'package:assignment_tracker_app/widgets/course_summary_card.dart';

class CourseDetailScreen extends ConsumerWidget {
  final String courseName;
  const CourseDetailScreen({super.key, required this.courseName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(mergedCoursesProvider);
    final student = ref.watch(selectedStudentProvider).value;
    final bands = ref.watch(dataProvider).value?.gradeBands;
    final range = ref.watch(dateRangeProvider).value;

    MergedCourse? course;
    for (final c in courses) {
      if (c.name == courseName) {
        course = c;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(course?.name ?? courseName),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.back('/'),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(dataProvider.notifier).refresh(),
          ),
        ],
      ),
      body: course == null || student == null || bands == null || range == null
          ? const Center(child: CircularProgressIndicator())
          : _Body(course: course, range: range, student: student, bands: bands),
    );
  }
}

class _Body extends StatelessWidget {
  final MergedCourse course;
  final DateRange range;
  final dynamic student;
  final dynamic bands;
  const _Body({
    required this.course,
    required this.range,
    required this.student,
    required this.bands,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final thresholds = student.scoreThresholds as Map<String, int>;
    final outstanding = [
      for (final it in course.items)
        if (range.contains(it.date) &&
            (isActionable(it, course.name, thresholds) ||
                it.status == 'half_credit_missing' ||
                it.status == 'not_graded'))
          it
    ]..sort((a, b) => (b.date ?? '').compareTo(a.date ?? ''));

    final synStatusLine = course.synergyPercent != null
        ? 'Synergy ${course.synergyLetter ?? ''} ${pctText(course.synergyPercent)}'
            '${course.policyHalfCredit && course.synergyAltHalfCreditPercent != null ? ' · half-credit-applied ${pctText(course.synergyAltHalfCreditPercent)}' : ''}'
        : (course.canvasAvgWithMissing != null
            ? 'Canvas worst-case ${pctText(course.canvasAvgWithMissing)}'
            : '—');

    return LayoutBuilder(builder: (ctx, c) {
      final wide = c.maxWidth >= 800;
      final maxW = wide ? 720.0 : c.maxWidth;
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: colors.card,
                  border: Border(
                    left: BorderSide(
                      width: 5,
                      color: gradeBandColor(
                          context,
                          courseClass(
                              course.synergyPercent ??
                                  course.canvasAvgWithMissing,
                              bands)),
                    ),
                    top: BorderSide(color: colors.border),
                    right: BorderSide(color: colors.border),
                    bottom: BorderSide(color: colors.border),
                  ),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(course.name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    if (course.teacher != null && course.teacher!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(course.teacher!,
                            style: TextStyle(
                                fontSize: 12, color: colors.textSecondary)),
                      ),
                    const SizedBox(height: 6),
                    Text(synStatusLine,
                        style: TextStyle(
                            fontSize: 12, color: colors.textMuted)),
                    const SizedBox(height: 4),
                    Text('${outstanding.length} open',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.textBody)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (outstanding.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No outstanding work flagged.',
                        style: TextStyle(color: colors.textMuted)),
                  ),
                )
              else
                for (final it in outstanding)
                  AssignmentCard(
                    item: it,
                    course: course,
                    onShowComments: () =>
                        showCommentsPanel(context, it, course),
                  ),
            ],
          ),
        ),
      );
    });
  }
}

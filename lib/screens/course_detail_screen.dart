import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/merged.dart';
import '../domain/priority.dart';
import '../state/data_providers.dart';
import '../state/prefs_providers.dart';
import '../state/priority_providers.dart';
import '../state/student_providers.dart';
import '../util/format.dart';
import '../widgets/assignment_card.dart';
import '../widgets/comments_panel.dart';
import '../widgets/course_summary_card.dart';

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
          onPressed: () => context.go('/'),
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
                  color: Colors.white,
                  border: Border(
                    left: BorderSide(
                      width: 5,
                      color: gradeBandColor(courseClass(
                          course.synergyPercent ?? course.canvasAvgWithMissing,
                          bands)),
                    ),
                    top: const BorderSide(color: Color(0xFFE3E3E3)),
                    right: const BorderSide(color: Color(0xFFE3E3E3)),
                    bottom: const BorderSide(color: Color(0xFFE3E3E3)),
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
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF666666))),
                      ),
                    const SizedBox(height: 6),
                    Text(synStatusLine,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF555555))),
                    const SizedBox(height: 4),
                    Text('${outstanding.length} open',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF333333))),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (outstanding.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No outstanding work flagged.',
                        style: TextStyle(color: Color(0xFF555555))),
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

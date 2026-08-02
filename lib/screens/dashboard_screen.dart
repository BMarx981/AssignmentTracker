import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:assignment_tracker_app/domain/merged.dart';
import 'package:assignment_tracker_app/domain/priority.dart';
import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:assignment_tracker_app/state/data_providers.dart';
import 'package:assignment_tracker_app/state/prefs_providers.dart';
import 'package:assignment_tracker_app/state/priority_providers.dart';
import 'package:assignment_tracker_app/state/student_providers.dart';
import 'package:assignment_tracker_app/theme/app_theme.dart';
import 'package:assignment_tracker_app/widgets/catch_up_row.dart';
import 'package:assignment_tracker_app/widgets/course_summary_card.dart';
import 'package:assignment_tracker_app/widgets/student_switcher.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(dataProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assignment Tracker'),
        actions: [
          const StudentSwitcher(),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(dataProvider.notifier).refresh(),
          ),
          IconButton(
            tooltip: 'Sign-off form',
            icon: const Icon(Icons.print_outlined),
            onPressed: () => context.go('/signoff'),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Failed to load: $e',
                style:
                    TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ),
        data: (payload) => const _DashboardBody(),
      ),
    );
  }
}

class _DashboardBody extends ConsumerStatefulWidget {
  const _DashboardBody();

  @override
  ConsumerState<_DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends ConsumerState<_DashboardBody> {
  bool _showCourses = false;

  @override
  Widget build(BuildContext context) {
    final payload = ref.watch(dataProvider).value;
    final student = ref.watch(selectedStudentProvider).value;
    final bands = payload?.gradeBands;
    final courses = ref.watch(mergedCoursesProvider);
    final range = ref.watch(dateRangeProvider).value;

    if (payload != null && payload.students.isEmpty) {
      return _EmptyState(onSettings: () => context.go('/settings'));
    }
    if (student == null || bands == null || range == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final catchUp = _buildCatchUpList(courses, range, student.assignmentStatus);
    final sortedCourses = [...courses]
      ..sort((a, b) => courseDistress(b).compareTo(courseDistress(a)));

    return RefreshIndicator(
      onRefresh: () => ref.read(dataProvider.notifier).refresh(),
      child: LayoutBuilder(
        builder: (ctx, c) {
          final cols = c.maxWidth >= 900
              ? 4
              : (c.maxWidth >= 600 ? 3 : 2);
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: _Summary(
                    studentName: student.name,
                    catchUpCount: catchUp.totalCount,
                  ),
                ),
              ),
              if (catchUp.totalCount == 0)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      "You're caught up. Nice.",
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.of(context).textMuted,
                          ),
                    ),
                  ),
                )
              else
                ..._buildCatchUpSlivers(
                    context, catchUp, student.assignmentStatus),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                sliver: SliverToBoxAdapter(
                  child: InkWell(
                    onTap: () =>
                        setState(() => _showCourses = !_showCourses),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 4),
                      child: Row(
                        children: [
                          Icon(
                            _showCourses
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 18,
                            color: AppColors.of(context).textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _showCourses
                                ? 'Hide courses'
                                : 'Show all courses',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.of(context).textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_showCourses)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.6,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final cc = sortedCourses[i];
                        return CourseSummaryCard(
                          course: cc,
                          bands: bands,
                          statusByKey: student.assignmentStatus,
                          range: range,
                          onTap: () => context.go(
                              '/course/${Uri.encodeComponent(cc.name)}'),
                        );
                      },
                      childCount: sortedCourses.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildCatchUpSlivers(
    BuildContext context,
    _CatchUpData data,
    Map<String, LocalStatus> statusByKey,
  ) {
    final slivers = <Widget>[];
    for (final group in data.groups) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          sliver: SliverToBoxAdapter(
            child: Text(
              group.course.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.of(context).textFaint,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => CatchUpRow(
                item: group.items[i],
                course: group.course,
                statusByKey: statusByKey,
              ),
              childCount: group.items.length,
            ),
          ),
        ),
      );
    }
    return slivers;
  }
}

/// Builds the recovery-focused list shown on the home screen. Includes only
/// items the student can still fix: missing, zero-graded, and
/// half-credit-missing. Sorts each course's items by due date (soonest first),
/// then groups by course (courses with most-overdue items first).
_CatchUpData _buildCatchUpList(
  List<MergedCourse> courses,
  DateRange range,
  Map<String, LocalStatus> statusByKey,
) {
  const recoveryStatuses = {'missing', 'zero_graded', 'half_credit_missing'};
  final groups = <_CatchUpGroup>[];
  for (final c in courses) {
    final items = c.items
        .where((it) =>
            recoveryStatuses.contains(it.status) && range.contains(it.date))
        // Suppress items the student already claimed handled (done-pending /
        // submitted-pending). Planned items stay — they're still owed.
        .where((it) {
          final ls = getLocalStatus(it, statusByKey);
          if (ls == null) return true;
          return ls.status == 'planned';
        })
        .toList()
      ..sort((a, b) {
        final da = _dueMillis(a.date);
        final db = _dueMillis(b.date);
        return da.compareTo(db);
      });
    if (items.isNotEmpty) {
      groups.add(_CatchUpGroup(course: c, items: items));
    }
  }
  groups.sort((a, b) {
    final ea = _dueMillis(a.items.first.date);
    final eb = _dueMillis(b.items.first.date);
    return ea.compareTo(eb);
  });
  return _CatchUpData(groups: groups);
}

int _dueMillis(String? date) {
  if (date == null || date.isEmpty) return 1 << 30;
  final s = date.length == 10 ? '${date}T00:00:00' : date;
  return DateTime.tryParse(s)?.millisecondsSinceEpoch ?? (1 << 30);
}

class _CatchUpData {
  final List<_CatchUpGroup> groups;
  const _CatchUpData({required this.groups});
  int get totalCount =>
      groups.fold(0, (sum, g) => sum + g.items.length);
}

class _CatchUpGroup {
  final MergedCourse course;
  final List<MergedItem> items;
  const _CatchUpGroup({required this.course, required this.items});
}

class _Summary extends StatelessWidget {
  final String studentName;
  final int catchUpCount;
  const _Summary({required this.studentName, required this.catchUpCount});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (catchUpCount == 0) {
      return Text(
        studentName,
        style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: colors.textStrong),
      );
    }
    final noun = catchUpCount == 1 ? 'thing' : 'things';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          studentName,
          style: TextStyle(
              fontSize: 13,
              color: colors.textFaint,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3),
        ),
        const SizedBox(height: 4),
        Text(
          'You have $catchUpCount $noun to catch up on.',
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: colors.textStrong,
              height: 1.25),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_outlined,
                size: 64, color: AppColors.of(context).iconMuted),
            const SizedBox(height: 16),
            const Text(
              'No data yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Add your Canvas token and Synergy credentials in Settings, '
              'then run a fetch to pull in your assignments.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.of(context).textSecondary),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Open Settings'),
              onPressed: onSettings,
            ),
          ],
        ),
      ),
    );
  }
}

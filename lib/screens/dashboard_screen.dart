import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/priority.dart';
import '../state/data_providers.dart';
import '../state/prefs_providers.dart';
import '../state/priority_providers.dart';
import '../state/student_providers.dart';
import '../widgets/course_summary_card.dart';
import '../widgets/priority_list_item.dart';
import '../widgets/student_switcher.dart';

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
                style: const TextStyle(color: Colors.red)),
          ),
        ),
        data: (payload) => _DashboardBody(),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final student = ref.watch(selectedStudentProvider).value;
    final bands = ref.watch(dataProvider).value?.gradeBands;
    final courses = ref.watch(mergedCoursesProvider);
    final top = ref.watch(top20Provider);
    final range = ref.watch(dateRangeProvider).value;

    if (student == null || bands == null || range == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final sortedCourses = [...courses]
      ..sort((a, b) => courseDistress(b).compareTo(courseDistress(a)));

    return RefreshIndicator(
      onRefresh: () => ref.read(dataProvider.notifier).refresh(),
      child: LayoutBuilder(
        builder: (ctx, c) {
          final wide = c.maxWidth >= 900;
          final cols = wide ? 4 : (c.maxWidth >= 600 ? 3 : 2);
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    '${student.name} · courses',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
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
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'Top 20 priority',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              if (top.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Text(
                      'Nothing actionable.',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final r = top[i];
                        return PriorityListItem(
                          index: i,
                          ranked: r,
                          statusByKey: student.assignmentStatus,
                          onTap: () => context.go(
                              '/course/${Uri.encodeComponent(r.course.name)}'),
                        );
                      },
                      childCount: top.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

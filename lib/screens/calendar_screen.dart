import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:assignment_tracker_app/domain/calendar.dart';
import 'package:assignment_tracker_app/domain/merged.dart';
import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:assignment_tracker_app/router.dart';
import 'package:assignment_tracker_app/state/calendar_providers.dart';
import 'package:assignment_tracker_app/state/priority_providers.dart';
import 'package:assignment_tracker_app/state/student_providers.dart';
import 'package:assignment_tracker_app/theme/app_theme.dart';
import 'package:assignment_tracker_app/util/format.dart';
import 'package:assignment_tracker_app/widgets/assignment_card.dart';
import 'package:assignment_tracker_app/widgets/comments_panel.dart';
import 'package:assignment_tracker_app/widgets/student_switcher.dart';

/// Month / two-week / week view of the selected child's assignments and
/// Canvas events. Pass [courseName] to show a single class.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key, this.courseName});

  final String? courseName;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  // table_calendar works in UTC midnights; ymd() reads them back as the same
  // calendar date the entries are keyed by.
  static DateTime _today() {
    final n = DateTime.now();
    return DateTime.utc(n.year, n.month, n.day);
  }

  DateTime _focused = _today();
  DateTime _selected = _today();
  CalendarFormat _format = CalendarFormat.month;

  bool get _scoped => widget.courseName != null;

  @override
  Widget build(BuildContext context) {
    final student = ref.watch(selectedStudentProvider).value;
    final courses = ref.watch(mergedCoursesProvider);
    final byDay = ref.watch(calendarEntriesProvider(widget.courseName ?? ''));
    final filter = student == null
        ? const CalendarFilter()
        : ref.watch(calendarFilterProvider(student.studentId));
    final slots = courseColorSlots(courses);
    final filterActive = _scoped
        ? filter.hiddenKinds.isNotEmpty || filter.hiddenStatuses.isNotEmpty
        : !filter.isDefault;
    final eventsError = filter.hiddenKinds.contains(CalendarKind.events)
        ? null
        : student?.canvas?.eventsError;

    return Scaffold(
      appBar: AppBar(
        title: Text(_scoped ? widget.courseName! : 'Calendar'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.back('/'),
        ),
        actions: [
          if (!_scoped) const StudentSwitcher(),
          IconButton(
            tooltip: 'Today',
            icon: const Icon(Icons.today_outlined),
            onPressed: () => setState(() => _focused = _selected = _today()),
          ),
          IconButton(
            tooltip: 'Filters',
            icon: Badge(
              isLabelVisible: filterActive,
              smallSize: 8,
              child: const Icon(Icons.filter_list),
            ),
            onPressed: student == null
                ? null
                : () => _showFilterSheet(
                      context,
                      studentId: student.studentId,
                      courses: courses,
                      slots: slots,
                      showClasses: !_scoped,
                    ),
          ),
        ],
      ),
      body: student == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (ctx, c) {
              final calendar = _buildCalendar(context, byDay, slots);
              final notices = [
                if (filterActive)
                  _FilterNotice(
                    onClear: () => ref
                        .read(calendarFilterProvider(student.studentId).notifier)
                        .reset(),
                  ),
                if (eventsError != null) _ErrorNotice(text: eventsError),
              ];
              final day = _DayHeader(day: _selected);
              final entries = byDay[ymd(_selected)] ?? const <CalendarEntry>[];
              final list = [
                for (final e in entries)
                  _EntryTile(entry: e, accent: slots[e.course.name] ?? 0),
                if (entries.isEmpty)
                  _EmptyDay(filterActive: filterActive),
              ];

              if (c.maxWidth >= 900) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 440,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                        children: [calendar, const _Legend(), ...notices],
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        children: [day, ...list],
                      ),
                    ),
                  ],
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                children: [calendar, const _Legend(), ...notices, day, ...list],
              );
            }),
    );
  }

  Widget _buildCalendar(
    BuildContext context,
    Map<String, List<CalendarEntry>> byDay,
    Map<String, int> slots,
  ) {
    final colors = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    return TableCalendar<CalendarEntry>(
      firstDay: DateTime.utc(now.year - 1, 1, 1),
      lastDay: DateTime.utc(now.year + 1, 12, 31),
      focusedDay: _focused,
      currentDay: _today(),
      selectedDayPredicate: (d) => isSameDay(d, _selected),
      calendarFormat: _format,
      availableCalendarFormats: const {
        CalendarFormat.month: 'Month',
        CalendarFormat.twoWeeks: '2 weeks',
        CalendarFormat.week: 'Week',
      },
      onFormatChanged: (f) => setState(() => _format = f),
      onDaySelected: (sel, foc) => setState(() {
        _selected = sel;
        _focused = foc;
      }),
      // Not setState: table_calendar owns the page; this only remembers it so
      // a rebuild doesn't jump back.
      onPageChanged: (foc) => _focused = foc,
      eventLoader: (d) => byDay[ymd(d)] ?? const [],
      startingDayOfWeek: StartingDayOfWeek.sunday,
      headerStyle: HeaderStyle(
        titleCentered: true,
        formatButtonShowsNext: false,
        titleTextStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.textStrong),
        leftChevronIcon: Icon(Icons.chevron_left, color: colors.textBody),
        rightChevronIcon: Icon(Icons.chevron_right, color: colors.textBody),
        formatButtonDecoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        formatButtonTextStyle:
            TextStyle(fontSize: 13, color: colors.textBody),
      ),
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: TextStyle(fontSize: 12, color: colors.textSecondary),
        weekendStyle: TextStyle(fontSize: 12, color: colors.textFaint),
      ),
      calendarStyle: CalendarStyle(
        defaultTextStyle: TextStyle(color: colors.textBody),
        weekendTextStyle: TextStyle(color: colors.textMuted),
        outsideTextStyle: TextStyle(color: colors.gradeHidden),
        todayDecoration: BoxDecoration(
            color: scheme.primaryContainer, shape: BoxShape.circle),
        todayTextStyle: TextStyle(
            color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700),
        selectedDecoration:
            BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
        selectedTextStyle:
            TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w700),
      ),
      calendarBuilders: CalendarBuilders(
        // A day with something missing gets a red date. The dots stay in class
        // colors: a red ring on a 6px dot drowned the color it was marking.
        defaultBuilder: (ctx, day, _) {
          final missing = (byDay[ymd(day)] ?? const <CalendarEntry>[])
              .any((e) => e.status == CalendarStatus.missing);
          if (!missing) return null;
          return Center(
            child: Text('${day.day}',
                style: TextStyle(
                    color: colors.dangerText, fontWeight: FontWeight.w700)),
          );
        },
        markerBuilder: (ctx, day, entries) => entries.isEmpty
            ? null
            : Positioned(
                bottom: 3,
                left: 0,
                right: 0,
                child: _DayMarkers(entries: entries, slots: slots),
              ),
      ),
    );
  }
}

/// Up to five marks under a day number, one per entry, in the class's color:
/// a dot for an assignment, a square for an event.
class _DayMarkers extends StatelessWidget {
  const _DayMarkers({required this.entries, required this.slots});

  final List<CalendarEntry> entries;
  final Map<String, int> slots;

  static const _max = 5;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final shown = entries.take(_max);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final e in shown)
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 0.75),
            decoration: BoxDecoration(
              color: colors.courseAccent(slots[e.course.name] ?? 0),
              shape: e.event != null ? BoxShape.rectangle : BoxShape.circle,
              borderRadius:
                  e.event != null ? BorderRadius.circular(1.5) : null,
            ),
          ),
        if (entries.length > _max)
          Text('+',
              style: TextStyle(
                  fontSize: 9,
                  height: 0.7,
                  fontWeight: FontWeight.w700,
                  color: colors.textSecondary)),
      ],
    );
  }
}

/// Key to the grid's marks, since a parent shouldn't have to guess.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final style = TextStyle(fontSize: 11.5, color: colors.textSecondary);
    Widget mark(BoxShape shape) => Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: colors.textFaint,
            shape: shape,
            borderRadius:
                shape == BoxShape.rectangle ? BorderRadius.circular(1.5) : null,
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            mark(BoxShape.circle),
            Text('Assignment', style: style),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            mark(BoxShape.rectangle),
            Text('Canvas event', style: style),
          ]),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: 'Red date',
                  style: TextStyle(
                      color: colors.dangerText, fontWeight: FontWeight.w700)),
              const TextSpan(text: ' = something missing'),
            ]),
            style: style,
          ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        DateFormat('EEEE, MMMM d').format(day),
        style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w700, color: colors.textStrong),
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay({required this.filterActive});
  final bool filterActive;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          filterActive
              ? 'Nothing on this day matches the filters.'
              : 'Nothing due on this day.',
          style: TextStyle(color: colors.textMuted),
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.accent});
  final CalendarEntry entry;
  final int accent;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final color = colors.courseAccent(accent);
    final label = Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              entry.course.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
    final item = entry.item;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label,
          if (item != null)
            AssignmentCard(
              item: item,
              course: entry.course,
              onShowComments: () =>
                  showCommentsPanel(context, item, entry.course),
            )
          else
            _EventCard(event: entry.event!, accent: color),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.accent});
  final CanvasEvent event;
  final Color accent;

  String _when() {
    if (event.allDay) return 'All day';
    final s = event.startAt;
    if (s == null) return '';
    final t = DateFormat('h:mm a');
    final e = event.endAt;
    if (e == null || !e.isAfter(s)) return t.format(s);
    if (ymd(e) != ymd(s)) {
      return '${DateFormat('MMM d, h:mm a').format(s)} – '
          '${DateFormat('MMM d, h:mm a').format(e)}';
    }
    return '${t.format(s)} – ${t.format(e)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final url = event.htmlUrl;
    final where = event.locationName;
    final desc = event.description;
    // A rounded border must be one color, so the class stripe is a child the
    // clip trims rather than a colored left side.
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accent),
            Expanded(child: _content(colors, url, where, desc)),
          ],
        ),
      ),
    );
  }

  Widget _content(AppColors colors, String? url, String? where, String? desc) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: url == null
            ? null
            : () => launchUrl(Uri.parse(url),
                mode: LaunchMode.externalApplication),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.event_outlined, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(event.title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  if (url != null)
                    Icon(Icons.open_in_new, size: 14, color: colors.chevron),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [_when(), if (where != null && where.isNotEmpty) where]
                    .where((s) => s.isNotEmpty)
                    .join(' · '),
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              if (desc != null && desc.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(desc,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colors.textMuted)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterNotice extends StatelessWidget {
  const _FilterNotice({required this.onClear});
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: colors.info.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.filter_list, size: 16, color: colors.info.foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Filters are hiding some items.',
                style:
                    TextStyle(fontSize: 13, color: colors.info.foreground)),
          ),
          TextButton(onPressed: onClear, child: const Text('Show all')),
        ],
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.danger.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$text Assignments are unaffected; refetch Canvas to retry.',
          style: TextStyle(fontSize: 13, color: colors.danger.foreground)),
    );
  }
}

// ---------------------------------------------------------------------------
// filter sheet
// ---------------------------------------------------------------------------

const _statusLabels = {
  CalendarStatus.missing: 'Missing',
  CalendarStatus.upcoming: 'Upcoming',
  CalendarStatus.waiting: 'Turned in, not graded',
  CalendarStatus.graded: 'Graded',
};

void _showFilterSheet(
  BuildContext context, {
  required String studentId,
  required List<MergedCourse> courses,
  required Map<String, int> slots,
  required bool showClasses,
}) {
  final names = courses.map((c) => c.name).toSet().toList()..sort();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Consumer(builder: (ctx, ref, _) {
      final colors = AppColors.of(ctx);
      final filter = ref.watch(calendarFilterProvider(studentId));
      final n = ref.read(calendarFilterProvider(studentId).notifier);

      Widget heading(String text, {Widget? trailing}) => Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(text,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: colors.textFaint)),
                ),
                ?trailing,
              ],
            ),
          );

      return SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Filter calendar',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    onPressed: filter.isDefault ? null : n.reset,
                    child: const Text('Reset'),
                  ),
                ],
              ),
              heading('SHOW'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilterChip(
                  label: const Text('Assignments'),
                  selected:
                      !filter.hiddenKinds.contains(CalendarKind.assignments),
                  onSelected: (_) => n.toggleKind(CalendarKind.assignments),
                ),
                FilterChip(
                  label: const Text('Canvas events'),
                  selected: !filter.hiddenKinds.contains(CalendarKind.events),
                  onSelected: (_) => n.toggleKind(CalendarKind.events),
                ),
              ]),
              heading('ASSIGNMENT STATUS'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in CalendarStatus.values)
                  FilterChip(
                    label: Text(_statusLabels[s]!),
                    selected: !filter.hiddenStatuses.contains(s),
                    onSelected:
                        filter.hiddenKinds.contains(CalendarKind.assignments)
                            ? null
                            : (_) => n.toggleStatus(s),
                  ),
              ]),
              if (showClasses) ...[
                heading(
                  'CLASSES',
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    TextButton(
                      onPressed: filter.hiddenCourses.isEmpty
                          ? null
                          : () => n.setHiddenCourses(const {}),
                      child: const Text('All'),
                    ),
                    TextButton(
                      onPressed: () => n.setHiddenCourses(names.toSet()),
                      child: const Text('None'),
                    ),
                  ]),
                ),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final name in names)
                    FilterChip(
                      avatar: CircleAvatar(
                        backgroundColor:
                            colors.courseAccent(slots[name] ?? 0),
                        radius: 6,
                      ),
                      label: Text(name),
                      selected: !filter.hiddenCourses.contains(name),
                      showCheckmark: false,
                      onSelected: (_) => n.toggleCourse(name),
                    ),
                ]),
              ],
            ],
          ),
        ),
      );
    }),
  );
}

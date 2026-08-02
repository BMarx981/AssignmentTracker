// Synthetic Canvas + Synergy data for testing without live credentials.
//
// Everything is generated relative to `DateTime.now()` so a seed always lands
// inside the dashboard's default window (one month back, one month forward) —
// important over the summer, when a real fetch returns nothing useful and a
// static fixture would fall outside the range. The two deliberate exceptions
// (an out-of-range item and a no-due-date item) are labelled as such.
//
// The payloads match what `CanvasClient.fetchAll` / `SynergyClient.fetchAll`
// return, so seeding exercises the same DataAssembler → mergeData → priority
// path the real app uses. Nothing here is imported by release code paths; the
// Settings entry point is gated on `kDebugMode`.
//
// ---------------------------------------------------------------------------
// Naming convention
// ---------------------------------------------------------------------------
// Every assignment is titled `<middle school assignment> [<route it exercises>]`.
// `normalizeName` strips bracketed text, so the labels are free: they never
// affect Canvas↔Synergy name matching, `assignmentKey`, or anything else. Read
// the bracket to know why the row is here.
//
// ---------------------------------------------------------------------------
// Route coverage
// ---------------------------------------------------------------------------
// Milo (990001) — Canvas + Synergy, the everything student.
//   Language Arts 6   failing band · due-date badge family · score threshold ·
//                     Canvas-only rows (graded/submitted/excused/no-due-date) ·
//                     an out-of-range row · an in-class row · the
//                     "Thought I handed it in" and "Not sure" sheet states
//   Accelerated Math 6  at-risk band · every local-status claim shape ·
//                     "Tonight" and custom-date plan presets ·
//                     Canvas 'pending_review' and 'graded with no score'
//   Historical Inquiry 6  half-credit policy · comment thread with replies ·
//                     two teacher check-in flags in one course
//   Science 6         computed-percent-only grade · teacher with no email
//   Study Skills 6    no teacher at all · unknown status · null points
//   PE 6              healthy course, nothing outstanding
//
//   Between them the six courses seed all six AssignmentState values, so every
//   variant of the action sheet's current-state header is reachable, and four
//   teacher check-in groups: one with two items, one whose marker has a reply
//   (so ✓ leaves it alone), one on a teacher with no email, one on a course
//   with no teacher.
// Nora (990002) — Canvas + Synergy, high school. Source-disagreement rows and
//   a Canvas course with no Synergy counterpart (silently dropped).
// Otis (990003) — Canvas ONLY. Exercises the canvas-only-course branch,
//   `shortCourseName`, Canvas worst-case grading, and the legacy string form
//   of `current_grading_period`.
// Pearl (990004) — Synergy ONLY. Zero-percent course, no-grade course (the
//   distress fallback), and a course with no assignments at all.

// This library stays free of Flutter imports on purpose: `tool/seed_demo_data.dart`
// runs it under plain `dart run` to write the same files without launching the
// app. `demo_seed.dart` holds the LocalStore-facing wrapper.

import 'package:assignment_tracker_app/domain/assignment_situation.dart'
    show
        kNotSureNote,
        kSubmittedNotGradedNote,
        kTeacherCheckInNote,
        kThoughtHandedInNote;
import 'package:assignment_tracker_app/domain/name_utils.dart';
import 'package:assignment_tracker_app/domain/rewards.dart' show visitPoints;

/// The full demo dataset as LocalStore-relative paths → JSON-encodable values.
///
/// Returning a plain map rather than writing directly is what lets the same
/// data reach the store two ways: through `seedDemoData` in-app, or through the
/// command-line tool that writes into the OS Application Support directory.
///
/// Credentials are deliberately absent — seeding must never clobber a real
/// token the user still wants.
Map<String, Object> demoFiles(DateTime anchor) {
  final out = <String, Object>{
    'canvas_data.json': buildCanvasPayload(anchor),
    'synergy_data.json': buildSynergyPayload(anchor),
    'grade_bands.json': {'failing': 60, 'at_risk': 75},
  };
  for (final student in demoStudents) {
    final dir = 'students/${student.id}';
    out['$dir/score_thresholds.json'] = student.thresholds;
    out['$dir/comments.json'] = student.comments(anchor);
    out['$dir/assignment_status.json'] = {
      'entries': student.statusEntries(anchor),
    };
    out['$dir/rewards.json'] = student.rewards(anchor);
    out['$dir/excused_days.json'] = student.excusedDays(anchor);
  }
  return out;
}

// ---------------------------------------------------------------------------
// date helpers
// ---------------------------------------------------------------------------

String _day(DateTime anchor, int offsetDays) {
  final d = DateTime(anchor.year, anchor.month, anchor.day + offsetDays);
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Day offset of the weekend the action sheet's "Weekend" pill would plan for:
/// the coming Saturday, or today if it already is the weekend. Mirrors
/// `_comingWeekend` in the sheet so a seeded plan lands on that preset.
int _weekendOffset(DateTime anchor) {
  final wd = anchor.weekday;
  if (wd == DateTime.saturday || wd == DateTime.sunday) return 0;
  return DateTime.saturday - wd;
}

/// Day offsets of the last [count] school days ending at [anchor], oldest
/// first. A weekend anchor walks back to the Friday.
///
/// Seeded check-ins have to land on school days, not raw calendar days.
/// Weekends are skipped by the streak, so a run seeded on consecutive calendar
/// days would read as a different length depending on which weekday the demo
/// was seeded — and would silently bridge into the historical block behind it.
List<int> _schoolDayOffsets(DateTime anchor, int count) {
  final out = <int>[];
  var offset = 0;
  while (out.length < count) {
    final day = DateTime(anchor.year, anchor.month, anchor.day + offset);
    if (day.weekday != DateTime.saturday && day.weekday != DateTime.sunday) {
      out.add(offset);
    }
    offset--;
  }
  return out.reversed.toList(growable: false);
}

/// The school day Milo was out sick: the 4th of the 8 in his run, counting
/// back. Shared by his ledger (which has no check-in on it) and his excused
/// days (which is what stops that hole from resetting the run).
int _miloSickDay(DateTime anchor) => _schoolDayOffsets(anchor, 8)[3];

String _stamp(
  DateTime anchor,
  int offsetDays, {
  int hour = 23,
  int minute = 59,
}) {
  final d = DateTime.utc(
    anchor.year,
    anchor.month,
    anchor.day + offsetDays,
    hour,
    minute,
  );
  return d.toIso8601String();
}

// ---------------------------------------------------------------------------
// synergy
// ---------------------------------------------------------------------------

/// One Synergy assignment row, in the shape `_fetchClassData` produces.
///
/// [day] may be null to produce a row with no due date (never in range).
/// [points] may be null to exercise the "no points possible" formatting path.
Map<String, dynamic> _syn(
  DateTime anchor,
  int? day,
  String name, {
  double? points,
  double? score,
  required String status,
  String type = 'Practice / Preparation',
  String? comment,
}) {
  return {
    'date': day == null ? null : _day(anchor, day),
    'name': name,
    'type': type,
    'points_possible': points,
    'score': score,
    'status': status,
    'displayed_percent': (score != null && points != null && points > 0)
        ? (score / points * 100).round()
        : 0,
    'comment': comment ?? (status == 'missing' ? 'Missing' : null),
  };
}

/// A Synergy course record, post-`_postProcess` (missing_count already
/// counted, canvas_course_id / policy already attached).
Map<String, dynamic> _course(
  String name, {
  String? teacher,
  String? teacherEmail,
  String? letterGrade,
  double? percent,
  double? computedPercent,
  String? policy,
  String? canvasCourseId,
  required List<Map<String, dynamic>> assignments,
}) {
  return {
    'synergy_name': name,
    'teacher': teacher,
    'teacher_email': teacherEmail,
    'letter_grade': letterGrade,
    'percent': percent,
    'computed_percent': computedPercent,
    'missing_count': assignments.where((a) => a['status'] == 'missing').length,
    'policy': policy,
    'canvas_course_id': canvasCourseId,
    'assignments': assignments,
  };
}

Map<String, dynamic> buildSynergyPayload(DateTime anchor) {
  return {
    'source': 'Synergy ParentVUE (demo data)',
    'synergy_base_url': 'https://demo.example.invalid',
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'students': [
      {
        'student_id': _milo.id,
        'name': _milo.name,
        'courses': _miloSynergyCourses(anchor),
      },
      {
        'student_id': _nora.id,
        'name': _nora.name,
        'courses': _noraSynergyCourses(anchor),
      },
      // Otis is deliberately absent here — he is the Canvas-only student.
      {
        'student_id': _pearl.id,
        'name': _pearl.name,
        'courses': _pearlSynergyCourses(anchor),
      },
    ],
  };
}

// ---------------------------------------------------------------------------
// Milo — the everything student. Names carrying a seeded status or comment are
// pulled out as constants so the key never drifts from the row it points at.
// ---------------------------------------------------------------------------

const _laPoetrySlam =
    'Poetry Slam Reflection Sheet [missing · due today, teacher flag has a reply]';
const _laBookTalk =
    'Book Talk Slide Deck [missing · due in N days, marked "Not sure"]';
const _laReadingLog = 'Chapter Nine Reading Log [missing · overdue this week]';
const _laNarrative =
    'Personal Narrative Rough Draft [missing · long overdue, "Thought I handed it in"]';
const _laEssayTwo =
    'Character Analysis Essay Two [graded · local claim gets suppressed]';

const _mathPlannedTonight =
    'Fraction Decimal Conversion Practice [missing · planned, "Tonight" preset]';
const _mathPlannedCustom =
    'Angle Measure Practice Page [missing · planned, custom date pill]';
const _mathDoneNotTurnedIn =
    'Percent Increase Word Problems [missing · done but not turned in]';
const _mathSaysSubmitted =
    'Unit Rate Exit Ticket [zero graded · student says submitted on a date]';
const _mathSaysSubmittedNoDate =
    'Ratio Table Homework Set [missing · says submitted, no date recorded]';
const _mathPlannedNoDate =
    'Coordinate Plane Practice Sheet [missing · planned with no date picked]';

const _histDbqDraft =
    'Trade Network DBQ Rough Draft [missing · comment thread with replies]';
const _histRomeMap =
    'Ancient Rome Map Labeling [missing · on the teacher check-in list]';
const _histChapterEight =
    'Chapter Eight Reading Notes [half credit · also on the check-in list]';

const _sciPhaseChange =
    'Phase Change Diagram Homework [zero graded · check-in on a teacher with no email]';

const _studyBinderCheck =
    'Binder Organization Check [missing · check-in on a course with no teacher]';

List<Map<String, dynamic>> _miloSynergyCourses(DateTime anchor) => [
  // Failing band (57% < 60). Canvas-linked, so this course owns the merge
  // routes as well as every "when is it due" badge variant.
  _course(
    'Language Arts 6',
    teacher: 'Priya Raman',
    teacherEmail: 'praman@demo.invalid',
    letterGrade: 'F',
    percent: 57.0,
    canvasCourseId: '20604',
    assignments: [
      // badge reads "due today"
      _syn(anchor, 0, _laPoetrySlam, points: 10, score: 0, status: 'missing'),
      _syn(
        anchor,
        1,
        'Vocabulary Unit Seven Sentences [missing · badge reads due tomorrow]',
        points: 8,
        score: 0,
        status: 'missing',
      ),
      // badge reads "due in N days"
      _syn(anchor, 4, _laBookTalk, points: 15, score: 0, status: 'missing'),
      // badge reads "was due <day>" — overdue inside a week
      _syn(anchor, -3, _laReadingLog, points: 10, score: 0, status: 'missing'),
      // overdue past a week, so the badge degrades to a plain "missing"
      _syn(anchor, -14, _laNarrative, points: 20, score: 0, status: 'missing'),
      _syn(
        anchor,
        -6,
        'Spelling Pretest Packet [zero graded · 0.55 priority multiplier]',
        points: 5,
        score: 0,
        status: 'zero_graded',
      ),
      // `isInClassOnly` matches the leading "IC" → 0.25 priority multiplier and
      // a "likely in-class" badge.
      _syn(
        anchor,
        -8,
        'IC: Peer Review Workshop Circle [in class · deprioritized]',
        points: 5,
        score: 0,
        status: 'missing',
      ),
      _syn(
        anchor,
        9,
        'Theme And Evidence Essay Final [not graded · never actionable]',
        points: 40,
        status: 'not_graded',
        type: 'All Tasks / Assessments',
      ),
      _syn(
        anchor,
        -20,
        _laEssayTwo,
        points: 40,
        score: 25,
        status: 'graded',
        type: 'All Tasks / Assessments',
      ),
      // Older than the default one-month window, so nothing should render it.
      _syn(
        anchor,
        -45,
        'First Quarter Poetry Journal [missing · outside the date range]',
        points: 10,
        score: 0,
        status: 'missing',
      ),
    ],
  ),

  // At-risk band (63.5%). Canvas-linked. Every local-status claim shape lives
  // here, which is also what drives the "N pending" pill on the course card.
  _course(
    'Accelerated Math 6',
    teacher: 'Alicia James',
    teacherEmail: 'ajames@demo.invalid',
    letterGrade: 'D',
    percent: 63.5,
    canvasCourseId: '20601',
    assignments: [
      _syn(anchor, -5, _mathPlannedTonight, points: 5, score: 0, status: 'missing'),
      _syn(anchor, -6, _mathPlannedCustom, points: 8, score: 0, status: 'missing'),
      _syn(
        anchor,
        -4,
        _mathDoneNotTurnedIn,
        points: 5,
        score: 0,
        status: 'missing',
      ),
      _syn(
        anchor,
        -9,
        _mathSaysSubmitted,
        points: 4,
        score: 0,
        status: 'zero_graded',
      ),
      _syn(
        anchor,
        -7,
        _mathSaysSubmittedNoDate,
        points: 5,
        score: 0,
        status: 'missing',
      ),
      _syn(
        anchor,
        -2,
        _mathPlannedNoDate,
        points: 5,
        score: 0,
        status: 'missing',
      ),
      _syn(
        anchor,
        -11,
        'Unit Four Ratios And Percent Test [graded · merged with Canvas]',
        points: 25,
        score: 14,
        status: 'graded',
        type: 'All Tasks / Assessments',
      ),
      _syn(
        anchor,
        -16,
        'Variable Expression IXL Set [missing · Synergy-only row]',
        points: 5,
        score: 0,
        status: 'missing',
      ),
      _syn(
        anchor,
        4,
        'Data Display Unit Project [not graded · big upcoming points]',
        points: 30,
        status: 'not_graded',
        type: 'All Tasks / Assessments',
      ),
      _syn(
        anchor,
        -20,
        'Percent Cool Down Quiz [graded · nothing to do]',
        points: 6,
        score: 6,
        status: 'graded',
        type: 'All Tasks / Assessments',
      ),
    ],
  ),

  // Half-credit-for-missing-work policy: the course card reads
  // "Synergy · history rule" and distress uses the recomputed percent (65%),
  // not the 72% Synergy prints. `half_credit_missing` rows are deliberately
  // NOT actionable, but they do show in the catch-up list.
  _course(
    'Historical Inquiry 6',
    teacher: 'Marcus Bell',
    teacherEmail: 'mbell@demo.invalid',
    letterGrade: 'C',
    percent: 72.0,
    policy: 'half_credit_for_missing_work',
    assignments: [
      _syn(
        anchor,
        -15,
        'Chapter Seven Reading Notes [half credit · not actionable]',
        points: 6,
        status: 'half_credit_missing',
      ),
      _syn(anchor, -3, _histChapterEight, points: 6, status: 'half_credit_missing'),
      _syn(anchor, -9, _histDbqDraft, points: 10, score: 0, status: 'missing'),
      _syn(anchor, -12, _histRomeMap, points: 8, score: 0, status: 'missing'),
      _syn(
        anchor,
        -18,
        'Silk Road Primary Source Analysis [graded · nothing to do]',
        points: 10,
        score: 9,
        status: 'graded',
      ),
      _syn(
        anchor,
        -21,
        'Ancient Egypt Timeline Project [graded · nothing to do]',
        points: 20,
        score: 17,
        status: 'graded',
        type: 'All Tasks / Assessments',
      ),
      _syn(
        anchor,
        6,
        'Trade Network DBQ Final Copy [not graded · upcoming]',
        points: 25,
        status: 'not_graded',
        type: 'All Tasks / Assessments',
      ),
    ],
  ),

  // No official percent — forces the computed-percent path and the
  // "Synergy (est.)" label. No teacher email either, so "Talk to teacher"
  // falls back to the "No email on file for Dana Okafor." snackbar.
  _course(
    'Science 6',
    teacher: 'Dana Okafor',
    letterGrade: 'B+',
    computedPercent: 88.2,
    assignments: [
      _syn(
        anchor,
        -19,
        'Density Column Lab Report [graded · nothing to do]',
        points: 20,
        score: 18,
        status: 'graded',
      ),
      _syn(
        anchor,
        -12,
        'Matter Vocabulary Quiz [graded · nothing to do]',
        points: 10,
        score: 9,
        status: 'graded',
        type: 'All Tasks / Assessments',
      ),
      _syn(anchor, -5, _sciPhaseChange, points: 5, score: 0, status: 'zero_graded'),
      // `isInClassOnly` also matches "pre-questionnaire".
      _syn(
        anchor,
        -1,
        'Pre-Questionnaire: Ecosystem Survey [in class · deprioritized]',
        points: 5,
        score: 0,
        status: 'missing',
      ),
      _syn(
        anchor,
        8,
        'Chemical Reaction Lab Report [not graded · upcoming]',
        points: 20,
        status: 'not_graded',
      ),
    ],
  ),

  // No teacher on the record at all → "Talk to teacher" shows the
  // "No teacher email on file for this course." snackbar.
  _course(
    'Study Skills 6',
    letterGrade: 'B-',
    percent: 80.0,
    assignments: [
      _syn(anchor, -2, _studyBinderCheck, points: 5, score: 0, status: 'missing'),
      // Empty status → synStatusToFlag returns 'unknown': no badge, not
      // actionable, invisible everywhere. Here so the branch has a name.
      _syn(
        anchor,
        -10,
        'Weekly Planner Photo Upload [unknown status · renders nowhere]',
        points: 5,
        status: '',
      ),
      // points_possible null → "— pts" on the card, no "(N pts)" in the PDF,
      // and priorityScore falls back to a weight of 5.
      _syn(
        anchor,
        -4,
        'Locker Cleanout Checklist [missing · no points possible]',
        status: 'missing',
      ),
      _syn(
        anchor,
        3,
        'Goal Setting Reflection Form [not graded · upcoming]',
        points: 10,
        status: 'not_graded',
      ),
    ],
  ),

  // Healthy course: sorts to the bottom of the grid, contributes no catch-up
  // rows, and its detail screen shows "No outstanding work flagged."
  _course(
    'PE 6',
    teacher: 'Sam Whitfield',
    teacherEmail: 'swhitfield@demo.invalid',
    letterGrade: 'A',
    percent: 100.0,
    assignments: [
      _syn(
        anchor,
        -18,
        'Fitness Log Week Five [graded · nothing to do]',
        points: 10,
        score: 10,
        status: 'graded',
      ),
      _syn(
        anchor,
        -8,
        'Pickleball Participation Points [graded · nothing to do]',
        points: 10,
        score: 10,
        status: 'graded',
      ),
    ],
  ),
];

// ---------------------------------------------------------------------------
// Nora — high school, Canvas + Synergy, lighter load. Her rows focus on the
// cases where the two sources disagree about the same assignment.
// ---------------------------------------------------------------------------

const _algSubstitution =
    'Substitution Homework Six Point Two [missing · done but not turned in]';
const _bioMitosis =
    'Mitosis Reading Guide Packet [missing · single comment thread]';

List<Map<String, dynamic>> _noraSynergyCourses(DateTime anchor) => [
  _course(
    'Algebra 1',
    teacher: 'Rosa Delgado',
    teacherEmail: 'rdelgado@demo.invalid',
    letterGrade: 'A-',
    percent: 91.0,
    canvasCourseId: '30701',
    assignments: [
      _syn(anchor, -3, _algSubstitution, points: 5, score: 0, status: 'missing'),
      // Synergy says "not graded", Canvas says "unsubmitted" — the merged row
      // keeps the Synergy flag, so it is NOT actionable despite Canvas.
      _syn(
        anchor,
        5,
        'Systems Unit Six Test [not graded in Synergy · unsubmitted in Canvas]',
        points: 50,
        status: 'not_graded',
        type: 'All Tasks / Assessments',
      ),
      _syn(
        anchor,
        -17,
        'Systems Of Equations Quiz [graded · nothing to do]',
        points: 20,
        score: 19,
        status: 'graded',
        type: 'All Tasks / Assessments',
      ),
    ],
  ),
  _course(
    'Biology',
    teacher: 'Henry Osei',
    teacherEmail: 'hosei@demo.invalid',
    letterGrade: 'C+',
    percent: 78.5,
    assignments: [
      _syn(anchor, -6, _bioMitosis, points: 10, score: 0, status: 'missing'),
      _syn(
        anchor,
        -13,
        'Cell Organelle Diagram Poster [graded · nothing to do]',
        points: 15,
        score: 11,
        status: 'graded',
      ),
      _syn(
        anchor,
        3,
        'Osmosis Potato Core Lab [not graded · upcoming]',
        points: 25,
        status: 'not_graded',
      ),
    ],
  ),
  _course(
    'Spanish 2',
    teacher: 'Elena Castillo',
    teacherEmail: 'ecastillo@demo.invalid',
    letterGrade: 'B',
    percent: 85.0,
    canvasCourseId: '30703',
    assignments: [
      // Merges with a submitted Canvas row → carries both the "not yet graded"
      // and "submitted · awaiting grade" badges at once.
      _syn(
        anchor,
        -2,
        'Composicion Mi Rutina Diaria [not graded · Canvas says submitted]',
        points: 20,
        status: 'not_graded',
      ),
      _syn(
        anchor,
        -11,
        'Vocabulario Unidad Cuatro [graded · nothing to do]',
        points: 10,
        score: 9,
        status: 'graded',
      ),
    ],
  ),
];

// ---------------------------------------------------------------------------
// Pearl — Synergy only, no Canvas record anywhere. Every row of hers renders
// the plain "Synergy" source badge.
// ---------------------------------------------------------------------------

const _preAlgRetake =
    'Order Of Operations Quiz Retake [missing · due today, planned for tomorrow]';
const _artValueScale =
    'Value Scale Shading Sheet [missing · course is sitting at zero percent]';

List<Map<String, dynamic>> _pearlSynergyCourses(DateTime anchor) => [
  _course(
    'Pre-Algebra 8',
    teacher: 'Gwen Marsh',
    teacherEmail: 'gmarsh@demo.invalid',
    letterGrade: 'F',
    percent: 42.0,
    assignments: [
      _syn(
        anchor,
        -12,
        'Integer Operations Practice Set [missing · deep failing course]',
        points: 10,
        score: 0,
        status: 'missing',
      ),
      _syn(
        anchor,
        -6,
        'One Step Equation Maze [missing · deep failing course]',
        points: 10,
        score: 0,
        status: 'missing',
      ),
      _syn(anchor, 0, _preAlgRetake, points: 15, score: 0, status: 'missing'),
      _syn(
        anchor,
        5,
        'Chapter Test Corrections Packet [not graded · upcoming]',
        points: 20,
        status: 'not_graded',
        type: 'All Tasks / Assessments',
      ),
    ],
  ),
  // percent 0.0 is not null, so the grade renders as a real 0% rather than the
  // em-dash placeholder — the far edge of the failing band.
  _course(
    'Art 8',
    teacher: 'Jules Ito',
    letterGrade: 'F',
    percent: 0.0,
    assignments: [
      _syn(anchor, -8, _artValueScale, points: 25, score: 0, status: 'missing'),
      // No due date at all → never inside any date range, so it renders
      // nowhere. Here so the branch has a name.
      _syn(
        anchor,
        null,
        'Sketchbook Check Whenever [missing · no due date, never in range]',
        points: 10,
        score: 0,
        status: 'missing',
      ),
      _syn(
        anchor,
        -2,
        'Clay Pinch Pot Glazing [missing · no points possible]',
        status: 'missing',
      ),
    ],
  ),
  // No percent and no computed percent → the card reads "No grade yet", the
  // band is uncolored, and courseDistress falls back to its flat 50.
  _course(
    'Choir 8',
    teacher: 'Ravi Nunes',
    teacherEmail: 'rnunes@demo.invalid',
    assignments: [
      _syn(
        anchor,
        -5,
        'Sight Reading Practice Log [missing · course has no grade at all]',
        points: 10,
        score: 0,
        status: 'missing',
      ),
      _syn(
        anchor,
        -10,
        'Concert Attendance Form [unknown status · renders nowhere]',
        points: 5,
        status: '',
      ),
    ],
  ),
  // A course with nothing in it: card with no pills, detail screen shows
  // "No outstanding work flagged."
  _course(
    'Study Hall 8',
    teacher: 'Ravi Nunes',
    teacherEmail: 'rnunes@demo.invalid',
    letterGrade: 'A',
    percent: 100.0,
    assignments: const [],
  ),
];

// ---------------------------------------------------------------------------
// canvas
// ---------------------------------------------------------------------------

/// One Canvas assignment in the trimmed shape `processStudent` writes.
///
/// [workflowState] is the *submission* state: graded | submitted |
/// pending_review | unsubmitted. Pass [excused] to exercise the excused branch,
/// and a null [day] for an assignment with no due date.
Map<String, dynamic> _canvasAssignment(
  DateTime anchor,
  int id,
  int? day,
  String name, {
  double? points,
  required String workflowState,
  double? score,
  bool excused = false,
}) {
  final handedIn = workflowState != 'unsubmitted';
  return {
    'id': id,
    'name': name,
    'due_at': day == null ? null : _stamp(anchor, day),
    'due_date': day == null ? null : _day(anchor, day),
    'points_possible': points,
    'html_url': 'https://demo.instructure.invalid/courses/0/assignments/$id',
    'submission_types': const ['online_upload'],
    'workflow_state': 'published',
    'omit_from_final_grade': false,
    'muted': false,
    'submission': {
      'workflow_state': workflowState,
      'submitted_at':
          handedIn ? _stamp(anchor, day ?? 0, hour: 18, minute: 4) : null,
      'missing': !handedIn && !excused,
      'late': false,
      'excused': excused,
      'score': score,
      'grade': score?.toString(),
      'entered_score': score,
      'graded_at':
          workflowState == 'graded' ? _stamp(anchor, (day ?? 0) + 2, hour: 9) : null,
    },
  };
}

Map<String, dynamic> buildCanvasPayload(DateTime anchor) {
  return {
    'source': 'Canvas (demo data)',
    'canvas_base_url': 'https://demo.instructure.invalid',
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'students': [
      {
        'student_id': _milo.id,
        'name': _milo.name,
        'canvas_user_id': 8801,
        'current_grading_period': {
          'title': 'Quarter 4',
          'start_date': _day(anchor, -45),
          'end_date': _day(anchor, 20),
        },
        'courses': _miloCanvasCourses(anchor),
        'generated_at': DateTime.now().toUtc().toIso8601String(),
      },
      {
        'student_id': _nora.id,
        'name': _nora.name,
        'canvas_user_id': 8802,
        'current_grading_period': {
          'title': 'Quarter 4',
          'start_date': _day(anchor, -45),
          'end_date': _day(anchor, 20),
        },
        'courses': _noraCanvasCourses(anchor),
        'generated_at': DateTime.now().toUtc().toIso8601String(),
      },
      {
        'student_id': _otis.id,
        'name': _otis.name,
        'canvas_user_id': 8803,
        // Older payloads stored the grading period as a bare title string;
        // CanvasData.fromJson accepts both, and this is the string branch.
        'current_grading_period': 'Quarter 4',
        'courses': _otisCanvasCourses(anchor),
        'generated_at': DateTime.now().toUtc().toIso8601String(),
      },
      // Pearl is deliberately absent here — she is the Synergy-only student.
    ],
  };
}

// Titles here deliberately echo the Synergy ones so nameSimilarity clears the
// 0.5 bar and the rows merge into source='both'. Everything else stays
// Canvas-only, which is the other branch worth looking at.
List<Map<String, dynamic>> _miloCanvasCourses(DateTime anchor) => [
  {
    'id': 20601,
    'name': 'Accelerated Math 6-JAMES-YR-2026',
    'course_code': 'MATH6ACC',
    'current_score': 63.5,
    'current_grade': 'D',
    'assignments': [
      _canvasAssignment(
        anchor,
        991001,
        -5,
        'Fraction Decimal Conversion Practice [Canvas twin · merges to both]',
        points: 5,
        workflowState: 'unsubmitted',
      ),
      _canvasAssignment(
        anchor,
        991002,
        -11,
        'Unit Four Ratios And Percent Test [Canvas twin · graded on both sides]',
        points: 25,
        workflowState: 'graded',
        score: 14,
      ),
      _canvasAssignment(
        anchor,
        991004,
        7,
        'Khan Academy Warmup Set Five [Canvas only · missing and upcoming]',
        points: 8,
        workflowState: 'unsubmitted',
      ),
      // pending_review maps to the same 'submitted_pending' flag as 'submitted'.
      _canvasAssignment(
        anchor,
        991005,
        -1,
        'Geometry Rectangle Puzzle Poster [Canvas only · pending review]',
        points: 12,
        workflowState: 'pending_review',
      ),
      // Graded with no score falls through every branch of canvasStatus and
      // lands on 'other': no badge, not actionable.
      _canvasAssignment(
        anchor,
        991006,
        -3,
        'Mystery Points Bell Ringer [Canvas only · graded with no score]',
        points: 6,
        workflowState: 'graded',
      ),
    ],
  },
  {
    'id': 20604,
    'name': 'Language Arts 6-RAMAN-YR-2026',
    'course_code': 'LA6',
    'current_score': 57.0,
    'current_grade': 'F',
    'assignments': [
      _canvasAssignment(
        anchor,
        992010,
        0,
        'Poetry Slam Reflection Sheet [Canvas twin · merges to both]',
        points: 10,
        workflowState: 'unsubmitted',
      ),
      _canvasAssignment(
        anchor,
        992011,
        -3,
        'Chapter Nine Reading Log [Canvas twin · merges to both]',
        points: 10,
        workflowState: 'unsubmitted',
      ),
      _canvasAssignment(
        anchor,
        992012,
        -20,
        'Character Analysis Essay Two [Canvas twin · real grade suppresses claims]',
        points: 40,
        workflowState: 'graded',
        score: 25,
      ),
      // Canvas-only and graded at 60% — below the 70% threshold seeded for this
      // course, which is the only way a graded row stays actionable. (A
      // Synergy-sourced graded row flattens to 'ok' and the threshold never
      // sees it.)
      _canvasAssignment(
        anchor,
        992013,
        -13,
        'Greek Roots Vocabulary Quiz [Canvas only · graded under the threshold]',
        points: 20,
        workflowState: 'graded',
        score: 12,
      ),
      _canvasAssignment(
        anchor,
        992014,
        -11,
        'Prefix And Suffix Practice Quiz [Canvas only · graded over the threshold]',
        points: 20,
        workflowState: 'graded',
        score: 18,
      ),
      _canvasAssignment(
        anchor,
        992015,
        -2,
        'Poetry Podcast Recording Project [Canvas only · submitted, awaiting grade]',
        points: 15,
        workflowState: 'submitted',
      ),
      // Excused Canvas rows that match nothing in Synergy are dropped outright.
      _canvasAssignment(
        anchor,
        992016,
        -5,
        'Field Trip Makeup Worksheet [Canvas only · excused, so it disappears]',
        points: 10,
        workflowState: 'unsubmitted',
        excused: true,
      ),
      // No due date → never inside a date range, so it renders nowhere.
      _canvasAssignment(
        anchor,
        992017,
        null,
        'Extra Credit Word Search [Canvas only · no due date, never in range]',
        points: 5,
        workflowState: 'unsubmitted',
      ),
    ],
  },
];

List<Map<String, dynamic>> _noraCanvasCourses(DateTime anchor) => [
  {
    'id': 30701,
    'name': 'Algebra 1-DELGADO-YR-2026',
    'course_code': 'ALG1',
    'current_score': 91.0,
    'current_grade': 'A-',
    'assignments': [
      _canvasAssignment(
        anchor,
        993001,
        -3,
        'Substitution Homework Six Point Two [Canvas twin · merges to both]',
        points: 5,
        workflowState: 'unsubmitted',
      ),
      _canvasAssignment(
        anchor,
        993002,
        5,
        'Systems Unit Six Test [Canvas twin · sources disagree]',
        points: 50,
        workflowState: 'unsubmitted',
      ),
    ],
  },
  {
    'id': 30703,
    'name': 'Spanish 2-CASTILLO-YR-2026',
    'course_code': 'SPAN2',
    'current_score': 85.0,
    'current_grade': 'B',
    'assignments': [
      _canvasAssignment(
        anchor,
        994001,
        -2,
        'Composicion Mi Rutina Diaria [Canvas twin · submitted, awaiting grade]',
        points: 20,
        workflowState: 'submitted',
      ),
    ],
  },
  // No Synergy course points at 30705, and Nora has Synergy data, so mergeData
  // drops this whole course on the floor. Nothing below ever renders.
  {
    'id': 30705,
    'name': 'Yearbook Elective-CHEN-YR-2026',
    'course_code': 'YRBK',
    'current_score': 88.0,
    'current_grade': 'B+',
    'assignments': [
      _canvasAssignment(
        anchor,
        995001,
        -4,
        'Spread Layout Draft [Canvas course with no Synergy match · dropped]',
        points: 20,
        workflowState: 'unsubmitted',
      ),
    ],
  },
];

// ---------------------------------------------------------------------------
// Otis — Canvas only. With no Synergy courses, `hasSynergy` is false, so every
// Canvas course survives on its own: names run through shortCourseName, grades
// come from the Canvas worst-case average, and no course has a teacher.
// ---------------------------------------------------------------------------

List<Map<String, dynamic>> _otisCanvasCourses(DateTime anchor) => [
  {
    'id': 40801,
    'name': 'World Geography 7-NGUYEN-YR-2026',
    'course_code': 'GEO7',
    'current_score': 50.0,
    'current_grade': 'F',
    'assignments': [
      _canvasAssignment(
        anchor,
        995101,
        -4,
        'Ancient Trade Route Map [Canvas-only course · missing and overdue]',
        points: 20,
        workflowState: 'unsubmitted',
      ),
      _canvasAssignment(
        anchor,
        995102,
        -10,
        'Continent Landform Quiz [Canvas-only course · graded]',
        points: 20,
        workflowState: 'graded',
        score: 15,
      ),
      _canvasAssignment(
        anchor,
        995103,
        -7,
        'Latitude Longitude Practice [Canvas-only course · zero graded]',
        points: 10,
        workflowState: 'graded',
        score: 0,
      ),
      _canvasAssignment(
        anchor,
        995104,
        6,
        'Country Research Slides [Canvas-only course · missing, planned ahead]',
        points: 25,
        workflowState: 'unsubmitted',
      ),
    ],
  },
  {
    'id': 40802,
    'name': 'Intro To Coding 7-PATEL-S1-2026',
    'course_code': 'CS7',
    'current_score': 97.5,
    'current_grade': 'A',
    'assignments': [
      _canvasAssignment(
        anchor,
        995201,
        -9,
        'Scratch Animation Project [graded · nothing outstanding]',
        points: 30,
        workflowState: 'graded',
        score: 29,
      ),
      _canvasAssignment(
        anchor,
        995202,
        -2,
        'Loops Practice Set [graded · nothing outstanding]',
        points: 10,
        workflowState: 'graded',
        score: 10,
      ),
    ],
  },
  // Nothing graded at all → canvasAvgGraded is null and the worst-case average
  // is a flat 0%, the bottom of the failing band.
  {
    'id': 40803,
    'name': 'Health Seven-OSBORNE-Q3-2026',
    'course_code': 'HLTH7',
    'assignments': [
      _canvasAssignment(
        anchor,
        995301,
        -5,
        'Nutrition Label Scavenger Hunt [missing · Canvas worst case is zero]',
        points: 10,
        workflowState: 'unsubmitted',
      ),
      _canvasAssignment(
        anchor,
        995302,
        -1,
        'Sleep Habit Tracker [missing · Canvas worst case is zero]',
        points: 10,
        workflowState: 'unsubmitted',
      ),
    ],
  },
  // A Canvas course with no assignments and no Synergy match is skipped by
  // mergeData, so this one never appears in the grid.
  {
    'id': 40804,
    'name': 'Band Seven-KOWALSKI-YR-2026',
    'course_code': 'BAND7',
    'assignments': const [],
  },
];

// ---------------------------------------------------------------------------
// per-student local state
// ---------------------------------------------------------------------------

/// Keys must be built the same way the UI builds them, or seeded statuses and
/// comments attach to nothing. Merged (Canvas+Synergy) rows key off the Canvas
/// id; Synergy-only rows key off normalized course + assignment names.
String _synKey(String course, String name) =>
    assignmentKey(canvasId: null, courseName: course, assignmentName: name);

String _canvasKey(int id) =>
    assignmentKey(canvasId: '$id', courseName: null, assignmentName: null);

class DemoStudent {
  const DemoStudent({
    required this.id,
    required this.name,
    required this.thresholds,
    required this.comments,
    required this.statusEntries,
    this.rewards = _noRewards,
    this.excusedDays = _noExcusedDays,
  });

  final String id;
  final String name;
  final Map<String, int> thresholds;
  final Map<String, dynamic> Function(DateTime) comments;
  final Map<String, dynamic> Function(DateTime) statusEntries;

  /// The rewards ledger (`rewards.json` shape). Defaults to empty so at least
  /// one demo student exercises the rewards screen's empty state.
  final Map<String, dynamic> Function(DateTime) rewards;

  /// Parent-excused days (`excused_days.json` shape).
  final Map<String, dynamic> Function(DateTime) excusedDays;
}

Map<String, dynamic> _noRewards(DateTime _) =>
    const <String, dynamic>{'events': <Map<String, dynamic>>[]};

Map<String, dynamic> _noExcusedDays(DateTime _) =>
    const <String, dynamic>{'days': <Map<String, dynamic>>[]};

/// One reward-ledger entry. [id] must match the dedupe key the app would
/// generate for the same action (`<kind>:<assignmentKey>`), so re-doing a
/// seeded action doesn't pay out twice.
Map<String, dynamic> _reward(
  DateTime anchor,
  String id,
  String kind,
  int points,
  String label,
  int day,
) => {
  'id': id,
  'kind': kind,
  'points': points,
  // Noon UTC lands on the same calendar day in every real timezone, which
  // matters because the streak counts local days.
  'at': _stamp(anchor, day, hour: 12, minute: 0),
  'label': label,
};

Map<String, dynamic> _thread(
  DateTime anchor,
  String id,
  String text,
  String author,
  int day, {
  List<Map<String, dynamic>> replies = const [],
}) => {
  'id': id,
  'text': text,
  'author': author,
  'created_at': _stamp(anchor, day, hour: 19, minute: 12),
  'replies': replies,
};

Map<String, dynamic> _reply(
  DateTime anchor,
  String id,
  String text,
  String author,
  int day,
) => {
  'id': id,
  'text': text,
  'author': author,
  'created_at': _stamp(anchor, day, hour: 8, minute: 30),
};

final _milo = DemoStudent(
  id: '990001',
  name: 'Milo',
  // Language Arts is graded harshly, so anything at or below 70% still counts
  // as actionable — that is what makes the 60% vocabulary quiz show up.
  thresholds: const {'Language Arts 6': 70},
  comments: (anchor) => {
    // ---- flag markers, which is how the action sheet stores its three
    // "something's off" answers and what feeds the teacher check-in screen ----

    // teacherCheckIn state, on a merged row (Canvas key). The marker has a
    // reply, so the check-in screen's ✓ deliberately leaves it in place rather
    // than deleting the conversation with it.
    _canvasKey(992010): [
      _thread(
        anchor,
        'demo-f1',
        kTeacherCheckInNote,
        'me',
        -1,
        replies: [
          _reply(anchor, 'demo-r1', 'Ask if the late window is still open.', 'me', 0),
        ],
      ),
    ],
    // thoughtHandedIn state → the sheet opens on "Something's off".
    _synKey('Language Arts 6', _laNarrative): [
      _thread(anchor, 'demo-f2', kThoughtHandedInNote, 'me', -9),
    ],
    // unsure state → same group, different header line.
    _synKey('Language Arts 6', _laBookTalk): [
      _thread(anchor, 'demo-f3', kNotSureNote, 'me', -2),
    ],
    // Two flags in one course → the check-in screen offers "Email teacher
    // about all 2".
    _synKey('Historical Inquiry 6', _histRomeMap): [
      _thread(anchor, 'demo-f4', kTeacherCheckInNote, 'me', -6),
    ],
    _synKey('Historical Inquiry 6', _histChapterEight): [
      _thread(anchor, 'demo-f5', kTeacherCheckInNote, 'me', -2),
    ],
    // Flagged on a teacher with no email → "No email on file for Dana Okafor."
    _synKey('Science 6', _sciPhaseChange): [
      _thread(anchor, 'demo-f6', kTeacherCheckInNote, 'me', -3),
      _thread(
        anchor,
        'demo-c1',
        'Says the diagram printed blank in the lab.',
        'me',
        -4,
      ),
    ],
    // Flagged on a course with no teacher at all → "No teacher email on file
    // for this course."
    _synKey('Study Skills 6', _studyBinderCheck): [
      _thread(anchor, 'demo-f7', kTeacherCheckInNote, 'me', -1),
    ],

    // ---- ordinary comment threads ----

    // A thread with two replies — the deep path in the comments panel.
    _synKey('Historical Inquiry 6', _histDbqDraft): [
      _thread(
        anchor,
        'demo-c2',
        'Needs the outline handout before he can start this one.',
        'me',
        -8,
        replies: [
          _reply(anchor, 'demo-r2', 'Emailed Mr. Bell for a spare copy.', 'me', -7),
          _reply(anchor, 'demo-r3', 'Got it Tuesday. Draft is half done.', 'me', -5),
        ],
      ),
      // Predates the funnel rework: this marker is still written to
      // comments.json by older builds, and now renders as a plain comment.
      _thread(anchor, 'demo-c3', kSubmittedNotGradedNote, 'me', -4),
    ],
    // A comment on a merged row, so the key has to be the Canvas one.
    _canvasKey(992011): [
      _thread(
        anchor,
        'demo-c4',
        'Reading log is in the blue folder, not typed.',
        'me',
        -1,
      ),
    ],
  },
  statusEntries: (anchor) => {
    // Planned for today → the sheet's "Tonight" pill reads as selected. No
    // priority reduction, and "Student plans by …" in the sign-off PDF. Merged
    // row, so the key is the Canvas one.
    _canvasKey(991001): {
      'status': 'planned',
      'updated_at': _stamp(anchor, -2, hour: 20),
      'assignment_name': _mathPlannedTonight,
      'course_name': 'Accelerated Math 6',
      'planned_date': _day(anchor, 0),
    },
    // Planned for a date that matches none of the three presets → the sheet
    // falls back to the date pill, showing the date instead of "Pick a date…".
    _synKey('Accelerated Math 6', _mathPlannedCustom): {
      'status': 'planned',
      'updated_at': _stamp(anchor, -3, hour: 20),
      'assignment_name': _mathPlannedCustom,
      'course_name': 'Accelerated Math 6',
      'planned_date': _day(anchor, 9),
    },
    // Planned with no date → the badge degrades to "📅 plan: date" and the PDF
    // prints no claim at all.
    _synKey('Accelerated Math 6', _mathPlannedNoDate): {
      'status': 'planned',
      'updated_at': _stamp(anchor, -1, hour: 20),
      'assignment_name': _mathPlannedNoDate,
      'course_name': 'Accelerated Math 6',
    },
    // Done but not turned in → 0.40 multiplier and dropped from catch-up.
    _synKey('Accelerated Math 6', _mathDoneNotTurnedIn): {
      'status': 'complete_pending_submission',
      'updated_at': _stamp(anchor, -1, hour: 17),
      'assignment_name': _mathDoneNotTurnedIn,
      'course_name': 'Accelerated Math 6',
    },
    // Turned in on a known date → 0.20 multiplier, "Student says submitted
    // <date>" in the PDF.
    _synKey('Accelerated Math 6', _mathSaysSubmitted): {
      'status': 'submitted_pending_feedback',
      'updated_at': _stamp(anchor, -1, hour: 9),
      'assignment_name': _mathSaysSubmitted,
      'course_name': 'Accelerated Math 6',
      'submitted_date': _day(anchor, -1),
    },
    // Turned in, no date recorded → the PDF's "Student says already submitted"
    // branch.
    _synKey('Accelerated Math 6', _mathSaysSubmittedNoDate): {
      'status': 'submitted_pending_feedback',
      'updated_at': _stamp(anchor, -2, hour: 9),
      'assignment_name': _mathSaysSubmittedNoDate,
      'course_name': 'Accelerated Math 6',
    },
    // Attached to an item that IS graded — getLocalStatus suppresses it, so
    // this one must NOT appear on the assignment anywhere. It does still count
    // toward the "N pending" pill on the Language Arts card.
    _canvasKey(992012): {
      'status': 'submitted_pending_feedback',
      'updated_at': _stamp(anchor, -19, hour: 9),
      'assignment_name': _laEssayTwo,
      'course_name': 'Language Arts 6',
      'submitted_date': _day(anchor, -19),
    },
  },
  // A worked-in ledger: 179 points, a live 7-day check-in streak carrying the
  // escalated +8 rate, and a mix of earned and half-finished badges so the
  // badge case shows both states. Most entries are historical — assignments
  // that have long since fallen out of the visible date range — which is
  // exactly how a real ledger outlives the data it was earned on.
  // One school day in the middle of the run has nothing on it — Milo was
  // home sick — and the parent excused it. That's what keeps the run at 7
  // instead of resetting it to 3.
  excusedDays: (anchor) => {
    'days': [
      {'date': _day(anchor, _miloSickDay(anchor)), 'reason': 'Sick'},
    ],
  },
  rewards: (anchor) {
    // The live run, on school days — the streak skips weekends, so seeding on
    // raw calendar days would read as a different length depending on which
    // weekday the demo was seeded.
    final s = _schoolDayOffsets(anchor, 8);
    final sick = _miloSickDay(anchor);
    final worked = s.where((o) => o != sick).toList(growable: false);
    return {
      'events': [
        // Seven days of showing up around one excused day, priced the way
        // visitPoints() would have priced them as the run built: the sick day
        // is skipped, so the day after it is day 4 and not a fresh day 1.
        for (final (i, offset) in worked.indexed)
          _reward(anchor, 'visit:${_day(anchor, offset)}', 'visit',
              visitPoints(i + 1), 'Day ${i + 1} check-in', offset),

        // Recent work, on the same school days as the check-ins so it rides
        // the run rather than extending it.
        _reward(anchor, 'turnedIn:demo-h10', 'turnedIn', 10, 'Reading Log Week 7', s[1]),
        _reward(anchor, 'planned:demo-h11', 'planned', 2, 'Book Talk Slides', s[2]),
        _reward(anchor, 'teacherEmail:Historical Inquiry 6:${_day(anchor, s[4])}', 'teacherEmail', 15, 'Historical Inquiry 6', s[4]),
        _reward(anchor, 'turnedIn:demo-h12', 'turnedIn', 10, 'Chapter 7 Questions', s[4]),
        _reward(anchor, 'finished:demo-h13', 'finished', 5, 'Math Practice Set B', s[5]),
        _reward(anchor, 'turnedIn:demo-h14', 'turnedIn', 10, 'Math Practice Set B', s[5]),
        _reward(anchor, 'planned:${_canvasKey(991001)}', 'planned', 2, _mathPlannedTonight, s[7]),
        _reward(anchor, 'planned:${_synKey('Accelerated Math 6', _mathPlannedCustom)}', 'planned', 2, _mathPlannedCustom, s[7]),

        // Everything older sits behind a gap wide enough to contain a school
        // day with nothing on it, so the run terminates where it should
        // instead of bridging back into this block.
        _reward(anchor, 'turnedIn:demo-h1', 'turnedIn', 10, 'Unit 1 Test Corrections', -44),
        _reward(anchor, 'turnedIn:demo-h2', 'turnedIn', 10, 'Cell Diagram Lab', -42),
        _reward(anchor, 'planned:demo-h3', 'planned', 2, 'Persuasive Essay Outline', -41),
        _reward(anchor, 'turnedIn:${_canvasKey(992012)}', 'turnedIn', 10, _laEssayTwo, -39),
        _reward(anchor, 'finished:demo-h4', 'finished', 5, 'Vocabulary Set 4', -38),
        _reward(anchor, 'turnedIn:demo-h5', 'turnedIn', 10, 'Vocabulary Set 4', -37),
        _reward(anchor, 'teacherEmail:Language Arts 6:${_day(anchor, -34)}', 'teacherEmail', 15, 'Language Arts 6', -34),
        _reward(anchor, 'turnedIn:demo-h6', 'turnedIn', 10, 'Rome Timeline', -32),
        _reward(anchor, 'planned:demo-h7', 'planned', 2, 'DBQ Draft', -29),
        _reward(anchor, 'turnedIn:demo-h8', 'turnedIn', 10, 'Reading Log Week 6', -28),
        _reward(anchor, 'finished:demo-h9', 'finished', 5, 'Science Phase Change Lab', -26),
      ],
    };
  },
);

final _nora = DemoStudent(
  id: '990002',
  name: 'Nora',
  thresholds: const {},
  comments: (anchor) => {
    _synKey('Biology', _bioMitosis): [
      _thread(anchor, 'demo-c5', 'Lost the packet, asked for a reprint.', 'me', -4),
      _thread(anchor, 'demo-f8', kTeacherCheckInNote, 'me', -3),
    ],
  },
  statusEntries: (anchor) => {
    _canvasKey(993001): {
      'status': 'complete_pending_submission',
      'updated_at': _stamp(anchor, -1, hour: 21),
      'assignment_name': _algSubstitution,
      'course_name': 'Algebra 1',
    },
  },
  // Just starting out: 23 points, level 0, and a 2-day streak — the shape the
  // dashboard pill takes before there is much to show.
  rewards: (anchor) {
    final s = _schoolDayOffsets(anchor, 2);
    return {
      'events': [
        _reward(anchor, 'visit:${_day(anchor, s[0])}', 'visit', 3, 'Day 1 check-in', s[0]),
        _reward(anchor, 'visit:${_day(anchor, s[1])}', 'visit', 3, 'Day 2 check-in', s[1]),
        _reward(anchor, 'planned:demo-n1', 'planned', 2, 'Mitosis Packet', s[0]),
        _reward(anchor, 'finished:${_canvasKey(993001)}', 'finished', 5, _algSubstitution, s[0]),
        _reward(anchor, 'turnedIn:demo-n2', 'turnedIn', 10, 'Lab Safety Quiz', s[1]),
      ],
    };
  },
);

final _otis = DemoStudent(
  id: '990003',
  name: 'Otis',
  thresholds: const {},
  comments: (anchor) => {
    _canvasKey(995101): [
      _thread(anchor, 'demo-c6', 'Map is started, needs the legend.', 'me', -2),
      // Canvas-only courses carry no teacher, so the check-in screen's email
      // button falls back to "No teacher email on file for this course."
      _thread(anchor, 'demo-f9', kTeacherCheckInNote, 'me', -2),
    ],
  },
  statusEntries: (anchor) => {
    // Planned for the coming Saturday → the sheet's "Weekend" pill reads as
    // selected. Also what puts a "1 pending" pill on a card whose grade comes
    // from the Canvas worst-case average.
    _canvasKey(995104): {
      'status': 'planned',
      'updated_at': _stamp(anchor, -1, hour: 18),
      'assignment_name': 'Country Research Slides',
      'course_name': 'World Geography 7',
      'planned_date': _day(anchor, _weekendOffset(anchor)),
    },
  },
);

final _pearl = DemoStudent(
  id: '990004',
  name: 'Pearl',
  thresholds: const {'Pre-Algebra 8': 65},
  comments: (anchor) => {
    _synKey('Art 8', _artValueScale): [
      _thread(anchor, 'demo-c7', 'Needs charcoal pencils from home.', 'me', -6),
      // Jules Ito has no email on file → the check-in screen names the teacher
      // in its snackbar instead of the course.
      _thread(anchor, 'demo-f10', kTeacherCheckInNote, 'me', -5),
    ],
  },
  statusEntries: (anchor) => {
    // Planned for tomorrow → the sheet's "Tomorrow" pill reads as selected.
    _synKey('Pre-Algebra 8', _preAlgRetake): {
      'status': 'planned',
      'updated_at': _stamp(anchor, 0, hour: 7),
      'assignment_name': _preAlgRetake,
      'course_name': 'Pre-Algebra 8',
      'planned_date': _day(anchor, 1),
    },
  },
  // A lapsed run: two days around the teacher email a few weeks back, then
  // nothing until today. Streak back to 1, best still 2 — the state the "come
  // back tomorrow" strip exists for, and proof that a real lapse (school days
  // missed, not a weekend) still resets.
  rewards: (anchor) {
    final recent = _schoolDayOffsets(anchor, 1);
    final old = _schoolDayOffsets(anchor, 12).take(2).toList();
    return {
      'events': [
        _reward(anchor, 'visit:${_day(anchor, old[0])}', 'visit', 3, 'Day 1 check-in', old[0]),
        _reward(anchor, 'visit:${_day(anchor, old[1])}', 'visit', 3, 'Day 2 check-in', old[1]),
        _reward(anchor, 'teacherEmail:Art 8:${_day(anchor, old[1])}', 'teacherEmail', 15, 'Art 8', old[1]),
        _reward(anchor, 'visit:${_day(anchor, recent[0])}', 'visit', 3, 'Day 1 check-in', recent[0]),
        _reward(anchor, 'planned:${_synKey('Pre-Algebra 8', _preAlgRetake)}', 'planned', 2, _preAlgRetake, recent[0]),
      ],
    };
  },
);

final demoStudents = <DemoStudent>[_milo, _nora, _otis, _pearl];

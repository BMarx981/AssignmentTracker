// What the student has already told us about one assignment.
//
// Two separate stores back this, and neither changes shape here:
//
//   * `assignment_status.json` — the mutually-exclusive status claim
//     (planned / complete_pending_submission / submitted_pending_feedback).
//   * `comments.json` — lightweight flags, stored as comment threads whose
//     text matches one of the `k*Note` constants below. That's how "talk to
//     teacher" and "thought I handed in" have always been persisted, so
//     reading them back as flags is free and backward compatible.
//
// `resolveSituation` folds both into one value the sheet can render, so the
// sheet never has to re-derive "has this person already answered?".

import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:assignment_tracker_app/util/format.dart';
import 'merged.dart';
import 'priority.dart';

/// Flag markers persisted as comment text. The first three predate the funnel
/// rework and must keep their exact wording — existing `comments.json` files
/// contain them verbatim.
const kTeacherCheckInNote = 'Need to talk to teacher about this.';
const kThoughtHandedInNote = 'I thought this was done and handed in.';
const kSubmittedNotGradedNote =
    "I think this is handed in but it hasn't been graded yet.";

/// Added by the "Not sure" action. New, but stored the same way as the others.
const kNotSureNote = 'Not sure what happened with this one.';

/// The single thing the sheet shows as "where this stands" when reopened.
/// Ordered by how strong a claim it is: an explicit status beats a flag.
enum AssignmentState {
  planned,
  doneNotSubmitted,
  submitted,
  thoughtHandedIn,
  unsure,
  teacherCheckIn,
}

/// The sheet's three disclosure groups. Used to decide which one to open when
/// a student reopens an assignment they've already answered for.
enum SheetGroup { plan, alreadyDid, somethingsOff }

class AssignmentSituation {
  const AssignmentSituation({
    this.status,
    this.thoughtHandedIn = false,
    this.teacherCheckIn = false,
    this.unsure = false,
  });

  /// The status claim, already filtered through [getLocalStatus] — so it is
  /// null once a real grade lands, same as everywhere else in the app.
  final LocalStatus? status;
  final bool thoughtHandedIn;
  final bool teacherCheckIn;
  final bool unsure;

  static const none = AssignmentSituation();

  AssignmentState? get state {
    switch (status?.status) {
      case 'planned':
        return AssignmentState.planned;
      case 'complete_pending_submission':
        return AssignmentState.doneNotSubmitted;
      case 'submitted_pending_feedback':
        return AssignmentState.submitted;
    }
    if (thoughtHandedIn) return AssignmentState.thoughtHandedIn;
    if (unsure) return AssignmentState.unsure;
    if (teacherCheckIn) return AssignmentState.teacherCheckIn;
    return null;
  }

  /// True when the student has answered before, so the sheet should open on
  /// the current-state header rather than the fresh chooser.
  bool get isRecorded => state != null;

  /// Which group to expand behind the current-state header.
  SheetGroup get group => switch (state) {
        AssignmentState.planned => SheetGroup.plan,
        AssignmentState.doneNotSubmitted ||
        AssignmentState.submitted =>
          SheetGroup.alreadyDid,
        _ => SheetGroup.somethingsOff,
      };

  /// One line for the current-state header. Student-facing wording.
  String get summary => switch (state) {
        AssignmentState.planned => () {
            final d = fmtPlanDate(status?.plannedDate);
            return d.isEmpty ? 'Planned' : 'Planned for $d';
          }(),
        AssignmentState.doneNotSubmitted => "Done, but not turned in yet",
        AssignmentState.submitted => 'Turned in, waiting on a grade',
        AssignmentState.thoughtHandedIn => 'You thought this was handed in',
        AssignmentState.unsure => "You weren't sure about this one",
        AssignmentState.teacherCheckIn => 'On your teacher check-in list',
        null => 'Nothing recorded yet',
      };
}

/// Folds the status entry and the comment flags for [item] into one value.
AssignmentSituation resolveSituation({
  required MergedItem item,
  required Map<String, LocalStatus> statusByKey,
  required Map<String, List<CommentThread>> comments,
}) {
  final threads = comments[item.key] ?? const <CommentThread>[];
  return AssignmentSituation(
    status: getLocalStatus(item, statusByKey),
    thoughtHandedIn: hasNote(threads, kThoughtHandedInNote),
    teacherCheckIn: hasNote(threads, kTeacherCheckInNote),
    unsure: hasNote(threads, kNotSureNote),
  );
}

/// Whether one of [threads] is the flag marker [note].
bool hasNote(List<CommentThread> threads, String note) =>
    threads.any((t) => t.text.trim() == note);

// MergedItem / MergedCourse + mergeData + buildMerged
// Direct port of mergeData() / buildMerged() / canvasStatus / synStatusToFlag
// from dashboard.html.

import '../models/api_models.dart';
import 'name_utils.dart';

/// Each MergedItem represents one assignment as the UI sees it: either Synergy-
/// only, Canvas-only, or merged. Fields mirror the JS `item` shape.
class MergedItem {
  final String source; // 'synergy' | 'canvas' | 'both'
  final String? canvasId;
  final String name;
  final String? date; // YYYY-MM-DD
  final double? pointsPossible;
  final double? score;
  final String status; // see synStatusToFlag / canvasStatus output
  final String? synergyStatus; // raw synergy status when source=synergy/both
  final String? canvasStatus; // raw canvas status when source=canvas/both
  final bool inClass;
  final String? htmlUrl;
  final String courseName;
  final Map<String, dynamic>? rawCanvas; // for hasRealGrade fallback

  const MergedItem({
    required this.source,
    this.canvasId,
    required this.name,
    this.date,
    this.pointsPossible,
    this.score,
    required this.status,
    this.synergyStatus,
    this.canvasStatus,
    this.inClass = false,
    this.htmlUrl,
    required this.courseName,
    this.rawCanvas,
  });

  MergedItem copyWith({
    String? source,
    String? canvasId,
    String? htmlUrl,
    String? canvasStatus,
  }) =>
      MergedItem(
        source: source ?? this.source,
        canvasId: canvasId ?? this.canvasId,
        name: name,
        date: date,
        pointsPossible: pointsPossible,
        score: score,
        status: status,
        synergyStatus: synergyStatus,
        canvasStatus: canvasStatus ?? this.canvasStatus,
        inClass: inClass,
        htmlUrl: htmlUrl ?? this.htmlUrl,
        courseName: courseName,
        rawCanvas: rawCanvas,
      );

  /// The key used for /api/assignments/{key}/{status,comments}.
  String get key => assignmentKey(
        canvasId: canvasId,
        courseName: courseName,
        assignmentName: name,
      );
}

class MergedCourse {
  final String name;
  final String? teacher;
  final String? teacherEmail;
  final String? synergyLetter;
  final double? synergyPercent; // 0..1 fraction (matches JS where /100 was applied)
  final bool synergyPercentIsComputed;
  final int? synergyMissingCount;
  final bool policyHalfCredit;
  final double? synergyAltHalfCreditPercent; // 0..1
  final double? canvasAvgGraded; // 0..1
  final double? canvasAvgWithMissing; // 0..1
  final List<MergedItem> items;

  const MergedCourse({
    required this.name,
    this.teacher,
    this.teacherEmail,
    this.synergyLetter,
    this.synergyPercent,
    this.synergyPercentIsComputed = false,
    this.synergyMissingCount,
    this.policyHalfCredit = false,
    this.synergyAltHalfCreditPercent,
    this.canvasAvgGraded,
    this.canvasAvgWithMissing,
    this.items = const [],
  });
}

String synStatusToFlag(String? s) {
  if (s == null || s.isEmpty) return 'unknown';
  if (s == 'missing') return 'missing';
  if (s == 'half_credit_missing') return 'half_credit_missing';
  if (s == 'not_graded') return 'not_graded';
  if (s == 'zero_graded') return 'zero_graded';
  return 'ok';
}

String canvasStatus(CanvasAssignment a) {
  final sub = a.submission ?? const {};
  if (sub['excused'] == true) return 'excused';
  final ws = sub['workflow_state'] as String?;
  final pts = a.pointsPossible;
  final score = (sub['score'] as num?)?.toDouble();
  if (ws == 'graded' && score != null) {
    if ((pts ?? 0) > 0 && score == 0) return 'zero_graded';
    return 'graded';
  }
  if (ws == 'submitted' || ws == 'pending_review') return 'submitted_pending';
  if (sub['missing'] == true || ws == 'unsubmitted' || ws == null) {
    return 'missing';
  }
  return 'other';
}

List<MergedCourse> mergeData(CanvasData? canvas, SynergyData? synergy) {
  final canvasCourses = canvas?.courses ?? const <CanvasCourse>[];
  final synCourses = synergy?.courses ?? const <SynergyCourse>[];

  final synByCanvasId = <String, SynergyCourse>{
    for (final s in synCourses)
      if (s.canvasCourseId != null && s.canvasCourseId!.isNotEmpty)
        s.canvasCourseId!: s,
  };

  final hasSynergy = synCourses.isNotEmpty;
  final usedSyn = <SynergyCourse>{};
  final out = <MergedCourse>[];

  for (final cc in canvasCourses) {
    final cid = cc.raw['id']?.toString() ?? '';
    final syn = synByCanvasId[cid];
    if (syn != null) usedSyn.add(syn);
    if (hasSynergy && syn == null) continue;
    if ((cc.assignments).isEmpty && syn == null) continue;
    out.add(_buildMerged(cc, syn));
  }
  for (final s in synCourses) {
    if (usedSyn.contains(s)) continue;
    out.add(_buildMerged(null, s));
  }
  return out;
}

MergedCourse _buildMerged(CanvasCourse? cc, SynergyCourse? syn) {
  final courseName = syn?.synergyName ??
      (cc != null ? shortCourseName(cc.name) : '') ;
  final name = courseName.isEmpty ? '(unknown class)' : courseName;

  double? canvasAvgGraded;
  double? canvasAvgWithMissing;
  if (cc != null) {
    var earned = 0.0;
    var poss = 0.0;
    var missingPoss = 0.0;
    for (final a in cc.assignments) {
      final s = canvasStatus(a);
      final sub = a.submission ?? const {};
      final pts = a.pointsPossible;
      final score = (sub['score'] as num?)?.toDouble();
      if ((s == 'graded' || s == 'zero_graded') &&
          pts != null &&
          pts > 0 &&
          score != null) {
        earned += score;
        poss += pts;
      } else if (s == 'missing' && pts != null) {
        missingPoss += pts;
      }
    }
    canvasAvgGraded = poss > 0 ? earned / poss : null;
    final denom = poss + missingPoss;
    canvasAvgWithMissing = denom > 0 ? earned / denom : null;
  }

  final policyHalfCredit = syn?.policy == 'half_credit_for_missing_work';
  double? synergyAltHalfCreditPercent;
  if (syn != null && policyHalfCredit) {
    var earned = 0.0;
    var poss = 0.0;
    for (final a in syn.assignments) {
      if (a.pointsPossible == null) continue;
      var score = a.score;
      if (a.status == 'missing' || a.status == 'not_graded') {
        score = a.pointsPossible! * 0.5;
      } else if (score == null) {
        continue;
      }
      earned += score;
      poss += a.pointsPossible!;
    }
    synergyAltHalfCreditPercent = poss > 0 ? earned / poss : null;
  }

  final synergyPercent = syn?.percent != null
      ? syn!.percent! / 100
      : (syn?.computedPercent != null ? syn!.computedPercent! / 100 : null);
  final synergyPercentIsComputed =
      syn != null && syn.percent == null && syn.computedPercent != null;

  final items = <MergedItem>[];

  // 1) seed with synergy assignments
  final synItems = syn?.assignments ?? const <SynergyAssignment>[];
  for (final s in synItems) {
    items.add(MergedItem(
      source: 'synergy',
      canvasId: null,
      name: s.name,
      date: s.date,
      pointsPossible: s.pointsPossible,
      score: s.score,
      status: synStatusToFlag(s.status),
      synergyStatus: s.status,
      inClass: isInClassOnly(s.name),
      htmlUrl: null,
      courseName: name,
    ));
  }

  // 2) walk canvas; merge into synergy when matched by name similarity
  final canvasItems = cc?.assignments ?? const <CanvasAssignment>[];
  for (final a in canvasItems) {
    final cs = canvasStatus(a);
    var bestSim = 0.0;
    var bestIdx = -1;
    for (var i = 0; i < synItems.length; i++) {
      final sim = nameSimilarity(a.name, synItems[i].name);
      if (sim > bestSim) {
        bestSim = sim;
        bestIdx = i;
      }
    }
    if (bestSim >= 0.5 && bestIdx >= 0) {
      final synName = synItems[bestIdx].name;
      final idx = items.indexWhere(
          (it) => it.source == 'synergy' && it.name == synName);
      if (idx >= 0) {
        items[idx] = items[idx].copyWith(
          source: 'both',
          canvasId: a.raw['id']?.toString(),
          htmlUrl: a.htmlUrl ?? items[idx].htmlUrl,
          canvasStatus: cs,
        );
      }
      continue;
    }
    if (cs == 'excused') continue;
    final sub = a.submission ?? const {};
    items.add(MergedItem(
      source: 'canvas',
      canvasId: a.raw['id']?.toString(),
      name: a.name,
      date: a.dueDate ?? ((a.raw['due_at'] as String?)?.substring(0, 10)),
      pointsPossible: a.pointsPossible,
      score: (sub['score'] as num?)?.toDouble(),
      status: cs,
      canvasStatus: cs,
      inClass: isInClassOnly(a.name),
      htmlUrl: a.htmlUrl,
      courseName: name,
      rawCanvas: a.raw,
    ));
  }

  return MergedCourse(
    name: name,
    teacher: syn?.teacher,
    teacherEmail: syn?.teacherEmail,
    synergyLetter: syn?.letterGrade,
    synergyPercent: synergyPercent,
    synergyPercentIsComputed: synergyPercentIsComputed,
    synergyMissingCount: syn?.missingCount,
    policyHalfCredit: policyHalfCredit,
    synergyAltHalfCreditPercent: synergyAltHalfCreditPercent,
    canvasAvgGraded: canvasAvgGraded,
    canvasAvgWithMissing: canvasAvgWithMissing,
    items: items,
  );
}

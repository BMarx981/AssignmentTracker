// Date range + ranking. Direct ports of inRange / hasRealGrade /
// courseDistress / isActionable / getLocalStatus / priorityScore / courseClass
// from dashboard.html.

import 'dart:math' as math;

import '../models/api_models.dart';
import 'merged.dart';

class DateRange {
  final DateTime? start;
  final DateTime? end;
  const DateRange({this.start, this.end});

  bool contains(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return false;
    final s = dateStr.length == 10 ? '${dateStr}T00:00:00' : dateStr;
    final d = DateTime.tryParse(s);
    if (d == null) return false;
    if (start != null && d.isBefore(start!)) return false;
    if (end != null && d.isAfter(end!)) return false;
    return true;
  }
}

/// Has the item received an actual grade (so any local "Felix says…" claim
/// should be suppressed)?
bool hasRealGrade(MergedItem item) {
  if (item.score != null && item.pointsPossible != null) {
    if (item.status == 'graded' ||
        item.status == 'late_100' ||
        item.status == 'reassessed') {
      return true;
    }
    if (item.score! > 0) return true;
  }
  if (item.canvasStatus == 'graded') return true;
  final sub = item.rawCanvas?['submission'] as Map?;
  if (sub != null && sub['score'] != null) return true;
  return false;
}

double courseDistress(MergedCourse c) {
  if (c.policyHalfCredit && c.synergyAltHalfCreditPercent != null) {
    return math.max(0, 100 - c.synergyAltHalfCreditPercent! * 100);
  }
  if (c.synergyPercent != null) {
    return math.max(0, 100 - c.synergyPercent! * 100);
  }
  if (c.canvasAvgWithMissing != null) {
    return math.max(0, 100 - c.canvasAvgWithMissing! * 100);
  }
  return 50;
}

bool isActionable(
  MergedItem item,
  String courseName,
  Map<String, int> thresholds,
) {
  if (item.status == 'missing') return true;
  if (item.status == 'zero_graded') return true;
  if (item.status == 'half_credit_missing') return false;
  if (item.status == 'not_graded') return false;
  if (item.status == 'graded') {
    final threshold = thresholds[courseName] ?? 0;
    if (threshold > 0 &&
        item.score != null &&
        item.pointsPossible != null &&
        item.pointsPossible! > 0) {
      return (item.score! / item.pointsPossible! * 100) <= threshold;
    }
  }
  return false;
}

LocalStatus? getLocalStatus(
  MergedItem item,
  Map<String, LocalStatus> statusByKey,
) {
  final entry = statusByKey[item.key];
  if (entry == null) return null;
  if (hasRealGrade(item)) return null;
  return entry;
}

double priorityScore({
  required MergedItem item,
  required MergedCourse course,
  required DateTime today,
  required Map<String, int> thresholds,
  required Map<String, LocalStatus> statusByKey,
  required DateRange range,
}) {
  if (!isActionable(item, course.name, thresholds)) return -1;
  if (!range.contains(item.date)) return -1;

  final distress = courseDistress(course);
  DateTime? dueDate;
  if (item.date != null && item.date!.isNotEmpty) {
    final s = item.date!.length == 10 ? '${item.date}T00:00:00' : item.date!;
    dueDate = DateTime.tryParse(s);
  }
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  final daysFromTomorrow = dueDate != null
      ? dueDate.difference(tomorrow).inMilliseconds / 86400000.0
      : 9999.0;
  final urgency = 30 / (daysFromTomorrow.abs() + 1);
  final pts = item.pointsPossible ?? 5;
  final pointWeight = (math.log(pts + 1) / math.ln10) * 10;

  var mult = 1.0;
  if (item.status == 'zero_graded') mult = 0.55;
  if (item.inClass) mult *= 0.25;
  final ls = getLocalStatus(item, statusByKey);
  if (ls != null) {
    if (ls.status == 'submitted_pending_feedback') mult *= 0.20;
    if (ls.status == 'complete_pending_submission') mult *= 0.40;
  }
  return (distress * 0.6 + urgency * 0.3 + pointWeight * 0.1) * mult;
}

/// Color band for a course percent (0..1). Matches the JS `courseClass`.
String courseClass(double? p, GradeBands bands) {
  if (p == null) return 'none';
  if (p * 100 < bands.failing) return 'bad';
  if (p * 100 < bands.atRisk) return 'warn';
  return 'ok';
}

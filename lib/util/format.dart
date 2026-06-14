import 'package:intl/intl.dart';

String pctText(double? p) {
  if (p == null) return '—';
  return '${(p * 100).round()}%';
}

/// "Fri 6/13" — same shape as the JS fmtPlanDate.
String fmtPlanDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final s = iso.length == 10 ? '${iso}T00:00:00' : iso;
  final d = DateTime.tryParse(s);
  if (d == null) return iso;
  const dows = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final dow = dows[d.weekday - 1];
  return '$dow ${d.month}/${d.day}';
}

/// "Jun 13, 4:02 PM" — short timestamp for comments.
String fmtCommentDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return DateFormat('MMM d, h:mm a').format(d.toLocal());
}

/// "YYYY-MM-DD" plain date.
String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

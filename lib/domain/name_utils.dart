// Direct ports of normalizeName / tokenSet / nameSimilarity / shortCourseName /
// isInClassOnly / assignmentKey from dashboard.html. Keep behavior byte-identical
// — the assignmentKey result is the server-side key for /api/assignments/{key},
// so any drift silently breaks status/comments writes.

String shortCourseName(String? n) {
  if (n == null || n.isEmpty) return '';
  return n
      .replaceFirst(RegExp(r'-[A-Za-z]+-(YR|S1|S2|Q[1-4])-\d{4}\s*$'), '')
      .trim();
}

String normalizeName(String? s) {
  if (s == null || s.isEmpty) return '';
  return s
      .toLowerCase()
      .replaceFirst(
          RegExp(r'^(?:at|pp|nr|nrt|rt|r|ic|sup|meh)[\-_.:\s]+',
              caseSensitive: false),
          '')
      .replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' ')
      .replaceAll(
          RegExp(r'due\s*\d{1,2}[.\/-]\d{1,2}(?:[.\/-]\d{2,4})?',
              caseSensitive: false),
          ' ')
      .replaceAll(
          RegExp(r'\b\d{1,2}\s*pts?\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\b\d{1,2}[.\/]\d{1,2}\b'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Set<String> tokenSet(String? s) =>
    normalizeName(s).split(' ').where((t) => t.length >= 3).toSet();

double nameSimilarity(String? a, String? b) {
  final A = tokenSet(a);
  final B = tokenSet(b);
  if (A.isEmpty || B.isEmpty) return 0;
  var inter = 0;
  for (final t in A) {
    if (B.contains(t)) inter++;
  }
  return inter / (A.length < B.length ? A.length : B.length);
}

bool isInClassOnly(String? name) {
  if (name == null) return false;
  return RegExp(
          r'\b(ic|in[- ]?class|pre[- ]?questionnaire|post[- ]?questionnaire)\b',
          caseSensitive: false)
      .hasMatch(name);
}

/// Build the same assignment_key string the server expects.
/// `canvasId` non-null → `canvas_<id>` ; otherwise → `syn_<course>_<name>`.
String assignmentKey({
  required String? canvasId,
  required String? courseName,
  required String? assignmentName,
}) {
  if (canvasId != null && canvasId.isNotEmpty) return 'canvas_$canvasId';
  final cn = normalizeName(courseName).replaceAll(RegExp(r'\s+'), '_');
  final an = normalizeName(assignmentName).replaceAll(RegExp(r'\s+'), '_');
  return 'syn_${cn}_$an';
}

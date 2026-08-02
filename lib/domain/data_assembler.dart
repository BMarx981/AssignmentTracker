import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:assignment_tracker_app/storage/local_store.dart';

/// Builds the `DataPayload` the UI consumes by joining locally-stored Canvas
/// + Synergy fetches with per-student state (statuses, comments, thresholds)
/// and global grade bands.
///
/// Ports `_build_students_response` + the local-file branch of `/api/data`
/// from `tracker/routes/api.py`. The output JSON shape is identical, so
/// `DataPayload.fromJson` consumes it unchanged.
class DataAssembler {
  DataAssembler(this._store);

  final LocalStore _store;

  /// Reads everything from disk and assembles a `DataPayload`. Returns an
  /// empty payload (no students, default grade bands) on a fresh install.
  Future<DataPayload> assemble() async {
    final canvas = await _store.readCanvasData() ?? const <String, dynamic>{};
    final synergy = await _store.readSynergyData() ?? const <String, dynamic>{};
    final gradeBandsJson =
        await _store.readGradeBands() ?? const <String, dynamic>{};

    final students = await _mergeStudents(canvas: canvas, synergy: synergy);
    return DataPayload.fromJson({
      'students': students,
      'grade_bands': gradeBandsJson,
    });
  }

  /// The per-student join + per-student state attach. Mirrors
  /// `_build_students_response` and the loop that follows it in `api_data`.
  Future<List<Map<String, dynamic>>> _mergeStudents({
    required Map<String, dynamic> canvas,
    required Map<String, dynamic> synergy,
  }) async {
    final canvasStudents = (canvas['students'] as List?) ?? const [];
    final synergyStudents = (synergy['students'] as List?) ?? const [];
    final canvasTs = canvas['generated_at'] as String?;
    final synergyTs = synergy['generated_at'] as String?;

    final synById = <String, Map<String, dynamic>>{};
    for (final s in synergyStudents) {
      if (s is! Map) continue;
      final m = s.cast<String, dynamic>();
      final sid = '${m['student_id'] ?? ''}';
      if (sid.isNotEmpty) synById[sid] = m;
    }

    final seen = <String>{};
    final out = <Map<String, dynamic>>[];

    for (final cs in canvasStudents) {
      if (cs is! Map) continue;
      final c = cs.cast<String, dynamic>();
      final sid = '${c['student_id'] ?? ''}';
      seen.add(sid);
      final syn = synById[sid] ?? const <String, dynamic>{};
      out.add(await _withExtras(sid, {
        'student_id': sid,
        'name': c['name'] ?? syn['name'] ?? sid,
        'canvas': {
          'generated_at': canvasTs,
          'current_grading_period': c['current_grading_period'],
          'courses': (c['courses'] as List?) ?? const [],
        },
        'synergy': {
          'generated_at': synergyTs,
          'courses': (syn['courses'] as List?) ?? const [],
        },
      }));
    }

    for (final ss in synergyStudents) {
      if (ss is! Map) continue;
      final s = ss.cast<String, dynamic>();
      final sid = '${s['student_id'] ?? ''}';
      if (seen.contains(sid)) continue;
      out.add(await _withExtras(sid, {
        'student_id': sid,
        'name': s['name'] ?? sid,
        'canvas': {'generated_at': canvasTs, 'courses': const []},
        'synergy': {
          'generated_at': synergyTs,
          'courses': (s['courses'] as List?) ?? const [],
        },
      }));
    }

    return out;
  }

  Future<Map<String, dynamic>> _withExtras(
    String studentId,
    Map<String, dynamic> base,
  ) async {
    base['score_thresholds'] =
        await _store.readScoreThresholds(studentId) ?? const <String, dynamic>{};
    base['comments'] =
        await _store.readComments(studentId) ?? const <String, dynamic>{};
    base['assignment_status'] = await _store.readAssignmentStatus(studentId) ??
        const <String, dynamic>{'entries': <String, dynamic>{}};
    return base;
  }
}

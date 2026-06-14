import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// File-backed JSON store for all non-credential app state.
///
/// Replaces Firestore + the server's `*.json` files. Layout under the OS
/// Application Support directory:
///
/// ```
/// <appSupport>/state/
///   grade_bands.json
///   canvas_data.json        ← full multi-student fetch snapshot
///   synergy_data.json       ← full multi-student fetch snapshot
///   students/<student_id>/
///     assignment_status.json
///     comments.json
///     score_thresholds.json
/// ```
///
/// Canvas and Synergy fetches each produce a single payload covering all
/// students, so they're stored as top-level blobs. Per-student state
/// (statuses, comments, thresholds) lives in subdirectories so partial
/// updates don't rewrite unrelated students' data.
///
/// All writes are atomic (write-temp + rename) so a crash mid-write can't
/// corrupt a JSON file. Reads return `null` for missing files; callers decide
/// what the default is.
class LocalStore {
  LocalStore._(this._root);

  static LocalStore? _instance;

  /// Initializes and returns the singleton. Cheap to call repeatedly.
  static Future<LocalStore> instance() async {
    if (_instance != null) return _instance!;
    final base = await getApplicationSupportDirectory();
    final root = Directory('${base.path}/state');
    await root.create(recursive: true);
    return _instance = LocalStore._(root);
  }

  final Directory _root;

  String get rootPath => _root.path;

  // ---------- low-level ----------

  File _file(String relativePath) => File('${_root.path}/$relativePath');

  Future<Object?> _readJson(String relativePath) async {
    final f = _file(relativePath);
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeJson(String relativePath, Object value) async {
    final f = _file(relativePath);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(value), flush: true);
    await tmp.rename(f.path);
  }

  // ---------- grade bands (global) ----------

  Future<Map<String, dynamic>?> readGradeBands() async {
    final raw = await _readJson('grade_bands.json');
    return raw is Map ? raw.cast<String, dynamic>() : null;
  }

  Future<void> writeGradeBands(Map<String, dynamic> bands) =>
      _writeJson('grade_bands.json', bands);

  // ---------- raw fetch snapshots (multi-student blobs) ----------

  Future<Map<String, dynamic>?> readCanvasData() async {
    final raw = await _readJson('canvas_data.json');
    return raw is Map ? raw.cast<String, dynamic>() : null;
  }

  Future<void> writeCanvasData(Map<String, dynamic> data) =>
      _writeJson('canvas_data.json', data);

  Future<Map<String, dynamic>?> readSynergyData() async {
    final raw = await _readJson('synergy_data.json');
    return raw is Map ? raw.cast<String, dynamic>() : null;
  }

  Future<void> writeSynergyData(Map<String, dynamic> data) =>
      _writeJson('synergy_data.json', data);

  // ---------- per-student ----------

  String _studentDir(String studentId) => 'students/${_safeId(studentId)}';

  Future<Map<String, dynamic>?> readAssignmentStatus(String studentId) async {
    final raw = await _readJson('${_studentDir(studentId)}/assignment_status.json');
    return raw is Map ? raw.cast<String, dynamic>() : null;
  }

  Future<void> writeAssignmentStatus(
    String studentId,
    Map<String, dynamic> data,
  ) =>
      _writeJson('${_studentDir(studentId)}/assignment_status.json', data);

  Future<Map<String, dynamic>?> readComments(String studentId) async {
    final raw = await _readJson('${_studentDir(studentId)}/comments.json');
    return raw is Map ? raw.cast<String, dynamic>() : null;
  }

  Future<void> writeComments(
    String studentId,
    Map<String, dynamic> data,
  ) =>
      _writeJson('${_studentDir(studentId)}/comments.json', data);

  Future<Map<String, dynamic>?> readScoreThresholds(String studentId) async {
    final raw =
        await _readJson('${_studentDir(studentId)}/score_thresholds.json');
    return raw is Map ? raw.cast<String, dynamic>() : null;
  }

  Future<void> writeScoreThresholds(
    String studentId,
    Map<String, int> thresholds,
  ) =>
      _writeJson(
        '${_studentDir(studentId)}/score_thresholds.json',
        thresholds,
      );

  Future<void> deleteStudent(String studentId) async {
    final dir = Directory('${_root.path}/${_studentDir(studentId)}');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Lists every directory under `students/`. The names are sanitized
  /// student_ids; callers should already know the real IDs from elsewhere.
  Future<List<String>> listStudentDirs() async {
    final dir = Directory('${_root.path}/students');
    if (!await dir.exists()) return const [];
    final out = <String>[];
    await for (final entry in dir.list()) {
      if (entry is Directory) out.add(entry.path.split('/').last);
    }
    return out;
  }

  Future<void> wipe() async {
    if (await _root.exists()) await _root.delete(recursive: true);
    await _root.create(recursive: true);
  }
}

/// Strip filesystem-unfriendly characters from a student ID so it's safe to
/// use as a directory name. Synergy IDs are numeric so this is mostly a guard.
String _safeId(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

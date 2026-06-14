import 'package:dio/dio.dart';

import '../models/api_models.dart';
import 'auth_transport.dart';
import 'etag_interceptor.dart';

class ApiClient {
  final Dio _dio;

  ApiClient._(this._dio);

  static Future<ApiClient> create(AuthTransport transport) async {
    final dio = await transport.build();
    if (!dio.interceptors.any((i) => i is ETagInterceptor)) {
      dio.interceptors.add(ETagInterceptor());
    }
    return ApiClient._(dio);
  }

  // ---------- identity ----------
  Future<Me> me() async {
    final r = await _dio.get<Map<String, dynamic>>('/api/me');
    return Me.fromJson(r.data ?? {});
  }

  // ---------- students ----------
  Future<Map<String, dynamic>> students() async {
    final r = await _dio.get<Map<String, dynamic>>('/api/students');
    return r.data ?? const {};
  }

  Future<void> selectStudent(String studentId) =>
      _dio.post('/api/students/$studentId/select');

  // ---------- main data payload ----------
  Future<DataPayload> data() async {
    final r = await _dio.get<Map<String, dynamic>>('/api/data');
    return DataPayload.fromJson(r.data ?? const {});
  }

  // ---------- credentials ----------
  Future<Credentials> getCredentials() async {
    final r = await _dio.get<Map<String, dynamic>>('/api/credentials');
    return Credentials.fromJson(r.data ?? const {});
  }

  Future<void> setCredentials(Credentials c) =>
      _dio.post('/api/credentials', data: c.toJson());

  // ---------- assignment status ----------
  Future<void> setAssignmentStatus(String key, AssignmentStatusReq req) =>
      _dio.post('/api/assignments/$key/status', data: req.toJson());

  // ---------- comments ----------
  Future<List<CommentThread>> postComment(String key, CommentReq req) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/api/assignments/$key/comments',
      data: req.toJson(),
    );
    final threads = (r.data?['threads'] as List?) ?? const [];
    return threads
        .map((t) => CommentThread.fromJson((t as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<CommentThread>> deleteComment(
    String key,
    String commentId, {
    String? studentId,
    String? replyId,
  }) async {
    final qp = <String, dynamic>{};
    if (studentId != null) qp['student_id'] = studentId;
    if (replyId != null) qp['reply_id'] = replyId;
    final r = await _dio.delete<Map<String, dynamic>>(
      '/api/assignments/$key/comments/$commentId',
      queryParameters: qp,
    );
    final threads = (r.data?['threads'] as List?) ?? const [];
    return threads
        .map((t) => CommentThread.fromJson((t as Map).cast<String, dynamic>()))
        .toList();
  }

  // ---------- score thresholds ----------
  Future<void> setScoreThresholds(String studentId, Map<String, int> th) =>
      _dio.post('/api/score-thresholds',
          data: {'student_id': studentId, 'thresholds': th});

  // ---------- grade bands ----------
  Future<GradeBands> getGradeBands() async {
    final r = await _dio.get<Map<String, dynamic>>('/api/grade-bands');
    return GradeBands.fromJson(r.data ?? const {});
  }

  Future<GradeBands> setGradeBands(GradeBands b) async {
    final r = await _dio.post<Map<String, dynamic>>('/api/grade-bands',
        data: b.toJson());
    return GradeBands.fromJson(r.data ?? const {});
  }

  // ---------- fetch jobs ----------
  Future<void> triggerCanvasFetch() => _dio.post('/api/fetch/canvas');
  Future<void> triggerSynergyFetch() => _dio.post('/api/fetch/synergy');

  Future<FetchStatus> fetchStatus() async {
    final r = await _dio.get<Map<String, dynamic>>('/api/fetch/status');
    return FetchStatus.fromJson(r.data ?? const {});
  }
}

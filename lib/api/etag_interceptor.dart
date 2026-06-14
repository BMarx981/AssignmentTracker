import 'package:dio/dio.dart';

/// Caches the response body for any GET that the server marks with an ETag.
/// On the next request to the same path it injects `If-None-Match`; if the
/// server returns 304 we substitute the cached body. The Dio call still
/// resolves with status 200 to the caller — they only see "same data" or
/// "new data," not the cache mechanics.
class ETagInterceptor extends Interceptor {
  final Map<String, _CacheEntry> _cache = {};

  String _key(RequestOptions o) =>
      '${o.method} ${o.uri}'; // path + query already in uri

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.method.toUpperCase() == 'GET') {
      final hit = _cache[_key(options)];
      if (hit != null) {
        options.headers['If-None-Match'] = hit.etag;
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final etag = response.headers.value('etag') ??
        response.headers.value('ETag');
    if (response.requestOptions.method.toUpperCase() == 'GET' &&
        response.statusCode == 200 &&
        etag != null) {
      _cache[_key(response.requestOptions)] =
          _CacheEntry(etag: etag, body: response.data);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final r = err.response;
    if (r != null && r.statusCode == 304) {
      final hit = _cache[_key(err.requestOptions)];
      if (hit != null) {
        handler.resolve(Response(
          requestOptions: err.requestOptions,
          data: hit.body,
          statusCode: 200,
          headers: r.headers,
          extra: {'fromETagCache': true},
        ));
        return;
      }
    }
    handler.next(err);
  }
}

class _CacheEntry {
  final String etag;
  final dynamic body;
  const _CacheEntry({required this.etag, required this.body});
}

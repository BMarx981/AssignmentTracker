import 'package:dio/browser.dart';
import 'package:dio/dio.dart';

import '../config/env.dart';
import 'auth_transport.dart';

AuthTransport createAuthTransport() => WebAuthTransport();

class WebAuthTransport implements AuthTransport {
  Dio? _dio;

  @override
  Future<Dio> build() async {
    if (_dio != null) return _dio!;
    final dio = Dio(BaseOptions(
      baseUrl: Env.apiBaseUrl,
      followRedirects: true,
      maxRedirects: 5,
      validateStatus: (s) => s != null && s < 400,
    ));
    dio.httpClientAdapter = BrowserHttpClientAdapter()..withCredentials = true;
    _dio = dio;
    return dio;
  }

  @override
  Future<void> bootstrap(String email) async {
    final dio = await build();
    await dio.get('/', queryParameters: {'user': email});
  }

  @override
  Future<void> clear() async {
    // Browser owns the cookie store; redirect through /auth/logout.
    final dio = await build();
    await dio.get('/auth/logout', options: Options(validateStatus: (_) => true));
  }
}

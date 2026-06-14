import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../config/env.dart';
import 'auth_transport.dart';

AuthTransport createAuthTransport() => IoAuthTransport();

class IoAuthTransport implements AuthTransport {
  static const _secure = FlutterSecureStorage();
  static const _cookieKey = 'tracker_session_cookie';

  PersistCookieJar? _jar;
  Dio? _dio;

  Future<PersistCookieJar> _jarInstance() async {
    if (_jar != null) return _jar!;
    final dir = await getApplicationSupportDirectory();
    final storage = FileStorage('${dir.path}/.cookies');
    _jar = PersistCookieJar(storage: storage);
    await _hydrateFromSecureStorage(_jar!);
    return _jar!;
  }

  Future<void> _hydrateFromSecureStorage(PersistCookieJar jar) async {
    final raw = await _secure.read(key: _cookieKey);
    if (raw == null || raw.isEmpty) return;
    final uri = Uri.parse(Env.apiBaseUrl);
    final cookie = Cookie('tracker_session', raw);
    await jar.saveFromResponse(uri, [cookie]);
  }

  Future<void> _mirrorToSecureStorage(PersistCookieJar jar) async {
    final uri = Uri.parse(Env.apiBaseUrl);
    final cookies = await jar.loadForRequest(uri);
    final session =
        cookies.where((c) => c.name == 'tracker_session').toList();
    if (session.isEmpty) return;
    await _secure.write(key: _cookieKey, value: session.first.value);
  }

  @override
  Future<Dio> build() async {
    if (_dio != null) return _dio!;
    final jar = await _jarInstance();
    final dio = Dio(BaseOptions(
      baseUrl: Env.apiBaseUrl,
      followRedirects: true,
      maxRedirects: 5,
      validateStatus: (s) => s != null && s < 400,
    ));
    dio.interceptors.add(CookieManager(jar));
    _dio = dio;
    return dio;
  }

  @override
  Future<void> bootstrap(String email) async {
    final dio = await build();
    await dio.get('/', queryParameters: {'user': email});
    await _mirrorToSecureStorage(await _jarInstance());
  }

  @override
  Future<void> clear() async {
    await _secure.delete(key: _cookieKey);
    final jar = await _jarInstance();
    await jar.deleteAll();
  }
}

import 'package:dio/dio.dart';

import 'auth_transport_stub.dart'
    if (dart.library.io) 'auth_transport_io.dart';

abstract class AuthTransport {
  Future<Dio> build();
  Future<void> bootstrap(String email);
  Future<void> clear();

  static AuthTransport create() => createAuthTransport();
}

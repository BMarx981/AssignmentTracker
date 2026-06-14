// Bootstraps AuthTransport, runs the dev-mode `?user=` handshake once, and
// exposes a shared ApiClient. All other providers depend on `apiClientProvider`.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/auth_transport.dart';
import '../config/env.dart';

final authTransportProvider = Provider<AuthTransport>((ref) {
  return AuthTransport.create();
});

final apiClientProvider = FutureProvider<ApiClient>((ref) async {
  final transport = ref.watch(authTransportProvider);
  await transport.bootstrap(Env.devUser);
  return ApiClient.create(transport);
});

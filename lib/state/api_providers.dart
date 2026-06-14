// Core providers: storage, credentials, Canvas/Synergy clients, and a small
// AppRepository facade for CRUD that doesn't fit cleanly into the data flow.
//
// There is no longer a FastAPI server in the loop — all data lives in
// `LocalStore` and credentials in the OS keychain.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/canvas_client.dart';
import '../api/synergy_client.dart';
import '../config/env.dart';
import '../domain/data_assembler.dart';
import '../models/api_models.dart';
import '../storage/credentials_store.dart';
import '../storage/local_store.dart';

// ---------- storage ----------

final localStoreProvider = FutureProvider<LocalStore>((_) async {
  return LocalStore.instance();
});

final credentialsStoreProvider =
    Provider<CredentialsStore>((_) => CredentialsStore());

/// Canvas/Synergy credentials read from the keychain. Watch this to react when
/// the user updates them in the settings screen.
final credentialsProvider = FutureProvider<Credentials>((ref) async {
  return ref.watch(credentialsStoreProvider).read();
});

final dataAssemblerProvider = FutureProvider<DataAssembler>((ref) async {
  final store = await ref.watch(localStoreProvider.future);
  return DataAssembler(store);
});

// ---------- network clients (null when creds aren't configured) ----------

/// A Canvas client constructed from the current credentials, or `null` when
/// the Canvas token isn't set. Watchers should handle the null branch by
/// prompting the user to fill credentials in settings.
final canvasClientProvider = FutureProvider<CanvasClient?>((ref) async {
  final creds = await ref.watch(credentialsProvider.future);
  final token = creds.canvasToken;
  if (token == null || token.isEmpty) return null;
  return CanvasClient(
    baseUrl: (creds.canvasBaseUrl?.isNotEmpty ?? false)
        ? creds.canvasBaseUrl!
        : Env.defaultCanvasBaseUrl,
    token: token,
  );
});

final synergyClientProvider = FutureProvider<SynergyClient?>((ref) async {
  final creds = await ref.watch(credentialsProvider.future);
  final user = creds.synergyUsername;
  final pass = creds.synergyPassword;
  if (user == null || user.isEmpty || pass == null || pass.isEmpty) return null;
  return SynergyClient(
    baseUrl: (creds.synergyBaseUrl?.isNotEmpty ?? false)
        ? creds.synergyBaseUrl!
        : Env.defaultSynergyBaseUrl,
    username: user,
    password: pass,
  );
});

// ---------- app repository (CRUD facade used by settings screen) ----------

/// Thin wrapper that bundles the operations the settings screen needs:
/// reading/writing credentials, grade bands, and per-student score thresholds.
/// Everything else flows through the typed action providers.
class AppRepository {
  AppRepository({
    required this.ref,
    required this.credentials,
    required this.store,
  });

  final Ref ref;
  final CredentialsStore credentials;
  final LocalStore store;

  Future<Credentials> getCredentials() => credentials.read();

  Future<void> setCredentials(Credentials c) async {
    await credentials.write(c);
    ref.invalidate(credentialsProvider);
  }

  Future<GradeBands> getGradeBands() async {
    final raw = await store.readGradeBands() ?? const <String, dynamic>{};
    return GradeBands.fromJson(raw);
  }

  Future<GradeBands> setGradeBands(GradeBands b) async {
    final failing = b.failing.clamp(1, 99);
    final atRisk = b.atRisk.clamp(failing + 1, 100);
    final clamped = GradeBands(failing: failing, atRisk: atRisk);
    await store.writeGradeBands(clamped.toJson());
    return clamped;
  }

  Future<void> setScoreThresholds(
    String studentId,
    Map<String, int> thresholds,
  ) async {
    final cleaned = <String, int>{
      for (final e in thresholds.entries)
        if (e.value > 0) e.key: e.value.clamp(0, 100),
    };
    await store.writeScoreThresholds(studentId, cleaned);
  }
}

final appRepositoryProvider = FutureProvider<AppRepository>((ref) async {
  final store = await ref.watch(localStoreProvider.future);
  return AppRepository(
    ref: ref,
    credentials: ref.watch(credentialsStoreProvider),
    store: store,
  );
});

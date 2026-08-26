import 'dart:convert';
import 'dart:io' show Platform;

import 'package:assignment_tracker_app/models/api_models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'local_store.dart';

/// Persists API credentials.
///
/// On macOS / iOS / Android this is a JSON file inside the app's sandboxed
/// Application Support directory:
///   * Keychain on sandboxed macOS apps requires `keychain-access-groups`
///     entitlement, which in turn requires a real signing identity. That's
///     a hassle for a personal app.
///   * The sandbox container is only accessible by this app + Time Machine,
///     which is sufficient for a parent-facing assignment tracker.
///
/// On Windows there is no per-app sandbox — anything in %APPDATA% is readable
/// by every process running as the user — so credentials go through
/// flutter_secure_storage instead, which encrypts them with DPAPI.
class CredentialsStore {
  CredentialsStore();

  static const _windowsStorage = FlutterSecureStorage();
  static const _windowsKey = 'credentials';

  Future<Credentials> read() async {
    if (Platform.isWindows) {
      final raw = await _windowsStorage.read(key: _windowsKey);
      if (raw == null || raw.isEmpty) return const Credentials();
      try {
        return Credentials.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        return const Credentials();
      }
    }
    final store = await LocalStore.instance();
    final raw = await store.readCredentials();
    if (raw == null) return const Credentials();
    return Credentials.fromJson(raw);
  }

  Future<void> write(Credentials c) async {
    final map = _toMap(c);
    if (Platform.isWindows) {
      await _windowsStorage.write(key: _windowsKey, value: jsonEncode(map));
      return;
    }
    final store = await LocalStore.instance();
    await store.writeCredentials(map);
  }

  Future<void> clear() async {
    if (Platform.isWindows) {
      await _windowsStorage.delete(key: _windowsKey);
      return;
    }
    final store = await LocalStore.instance();
    await store.writeCredentials(const <String, dynamic>{});
  }

  Map<String, dynamic> _toMap(Credentials c) => <String, dynamic>{
    if ((c.canvasToken ?? '').isNotEmpty) 'canvas_token': c.canvasToken,
    if ((c.canvasBaseUrl ?? '').isNotEmpty) 'canvas_base_url': c.canvasBaseUrl,
    if ((c.synergyUsername ?? '').isNotEmpty)
      'synergy_username': c.synergyUsername,
    if ((c.synergyPassword ?? '').isNotEmpty)
      'synergy_password': c.synergyPassword,
    if ((c.synergyBaseUrl ?? '').isNotEmpty)
      'synergy_base_url': c.synergyBaseUrl,
  };
}

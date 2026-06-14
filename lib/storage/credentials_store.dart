import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/api_models.dart';

/// Persists API credentials in the OS keychain via `flutter_secure_storage`.
///
/// Replaces the server-side `credentials.json` / Secret Manager backing —
/// we're a single-user native app, so the device keychain is plenty.
class CredentialsStore {
  CredentialsStore({FlutterSecureStorage? storage})
      : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;

  static const _kCanvasToken = 'tracker.canvas_token';
  static const _kCanvasBaseUrl = 'tracker.canvas_base_url';
  static const _kSynergyUsername = 'tracker.synergy_username';
  static const _kSynergyPassword = 'tracker.synergy_password';
  static const _kSynergyBaseUrl = 'tracker.synergy_base_url';

  Future<Credentials> read() async {
    return Credentials(
      canvasToken: await _s.read(key: _kCanvasToken),
      canvasBaseUrl: await _s.read(key: _kCanvasBaseUrl),
      synergyUsername: await _s.read(key: _kSynergyUsername),
      synergyPassword: await _s.read(key: _kSynergyPassword),
      synergyBaseUrl: await _s.read(key: _kSynergyBaseUrl),
    );
  }

  Future<void> write(Credentials c) async {
    await _writeOrDelete(_kCanvasToken, c.canvasToken);
    await _writeOrDelete(_kCanvasBaseUrl, c.canvasBaseUrl);
    await _writeOrDelete(_kSynergyUsername, c.synergyUsername);
    await _writeOrDelete(_kSynergyPassword, c.synergyPassword);
    await _writeOrDelete(_kSynergyBaseUrl, c.synergyBaseUrl);
  }

  Future<void> clear() async {
    for (final k in const [
      _kCanvasToken,
      _kCanvasBaseUrl,
      _kSynergyUsername,
      _kSynergyPassword,
      _kSynergyBaseUrl,
    ]) {
      await _s.delete(key: k);
    }
  }

  Future<void> _writeOrDelete(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _s.delete(key: key);
    } else {
      await _s.write(key: key, value: value);
    }
  }
}

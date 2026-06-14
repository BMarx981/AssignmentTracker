import '../models/api_models.dart';
import 'local_store.dart';

/// Persists API credentials to a JSON file inside the app's sandboxed
/// Application Support directory.
///
/// We use plain JSON instead of the Keychain because:
///   * Keychain on sandboxed macOS apps requires `keychain-access-groups`
///     entitlement, which in turn requires a real signing identity. That's
///     a hassle for a personal app.
///   * The sandbox container is only accessible by this app + Time Machine,
///     which is sufficient for a parent-facing assignment tracker.
class CredentialsStore {
  CredentialsStore();

  Future<Credentials> read() async {
    final store = await LocalStore.instance();
    final raw = await store.readCredentials();
    if (raw == null) return const Credentials();
    return Credentials.fromJson(raw);
  }

  Future<void> write(Credentials c) async {
    final store = await LocalStore.instance();
    await store.writeCredentials(<String, dynamic>{
      if ((c.canvasToken ?? '').isNotEmpty) 'canvas_token': c.canvasToken,
      if ((c.canvasBaseUrl ?? '').isNotEmpty)
        'canvas_base_url': c.canvasBaseUrl,
      if ((c.synergyUsername ?? '').isNotEmpty)
        'synergy_username': c.synergyUsername,
      if ((c.synergyPassword ?? '').isNotEmpty)
        'synergy_password': c.synergyPassword,
      if ((c.synergyBaseUrl ?? '').isNotEmpty)
        'synergy_base_url': c.synergyBaseUrl,
    });
  }

  Future<void> clear() async {
    final store = await LocalStore.instance();
    await store.writeCredentials(const <String, dynamic>{});
  }
}

/// Build-time defaults for Canvas / Synergy.
///
/// Each can be overridden per-user via the credentials store (see
/// `CredentialsStore`). The values here are just the fallback when the user
/// hasn't set their own base URLs.
class Env {
  static const String defaultCanvasBaseUrl = String.fromEnvironment(
    'CANVAS_BASE_URL',
    defaultValue: 'https://mcpsmd.instructure.com',
  );

  static const String defaultSynergyBaseUrl = String.fromEnvironment(
    'SYNERGY_BASE_URL',
    defaultValue: 'https://md-mcps-psv.edupoint.com',
  );
}

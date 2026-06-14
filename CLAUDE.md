# assignment_tracker_app — Claude guidance

Flutter port of the FastAPI dashboard at `../assignment-tracker/`. Targets iOS, Android, and macOS. Web is intentionally not supported (CORS would force a server proxy back into the architecture; the plan is to call Canvas and Synergy directly from native clients).

## macOS notes

- Sandbox is on by default. Network entitlements live in `macos/Runner/DebugProfile.entitlements` and `Release.entitlements` — `com.apple.security.network.client` is required for any outbound HTTP. Without it, calls fail silently.
- Credentials use `flutter_secure_storage` (Keychain on macOS, same API as iOS).

## Required versions

- **Riverpod 3.x** (`flutter_riverpod: ^3.3.2`, `riverpod_annotation: ^4.x`). Do NOT downgrade to Riverpod 2 — the user explicitly requires Riverpod 3.x.
- **Dart SDK ^3.11** (`environment: sdk: ^3.11.5`).
- **dio ^5** for HTTP, never `package:http`.

## Riverpod 3 API reminders (differences from 2.x)

- `AsyncValue.value` is the **nullable** accessor (replaces 2.x `valueOrNull`). On `AsyncData<T>` it's non-nullable.
- Family providers: notifier class is a plain `AsyncNotifier<T>` (no `FamilyAsyncNotifier`). The family argument is passed to the notifier's constructor, e.g.:
  ```dart
  class HiddenCoursesNotifier extends AsyncNotifier<Set<String>> {
    HiddenCoursesNotifier(this.studentId);
    final String studentId;
    @override Future<Set<String>> build() async { /* use this.studentId */ }
  }
  final hiddenCoursesProvider = AsyncNotifierProvider
      .family<HiddenCoursesNotifier, Set<String>, String>(
        HiddenCoursesNotifier.new,
      );
  ```
- `riverpod_generator` does NOT support Riverpod 3 yet — write providers manually until it does.

## Backend

Backend stays on FastAPI. Auth (v1) is dev-mode only — bootstrap with `GET /?user=<email>`, the session cookie carries the rest.

## Cross-platform cookies

All targets are native (iOS, Android, macOS), so `dio_cookie_manager` + `PersistCookieJar` + `flutter_secure_storage` works uniformly — no conditional imports needed. The `lib/api/auth_transport*.dart` shim exists from the prior web target and can be collapsed once the FastAPI backend is removed.

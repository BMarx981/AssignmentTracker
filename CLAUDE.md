# assignment_tracker_app — Claude guidance

Flutter port of the FastAPI dashboard at `../assignment-tracker/`. Targets iOS, Android, and macOS. Web is intentionally not supported (CORS would force a server proxy back into the architecture; the plan is to call Canvas and Synergy directly from native clients).

## macOS notes

- Sandbox is on by default. Network entitlements live in `macos/Runner/DebugProfile.entitlements` and `Release.entitlements` — `com.apple.security.network.client` is required for any outbound HTTP. Without it, calls fail silently.
- Credentials are plain JSON in the sandboxed Application Support container (see `lib/storage/credentials_store.dart` for why not Keychain). `flutter_secure_storage` is a dependency but is only invoked on Windows.

## Windows notes

- No `windows/` runner yet — generate it on a Windows machine with `flutter create --platforms=windows --org com.brianmarx .` (Flutter cannot cross-compile Windows builds).
- Credentials go through `flutter_secure_storage` (DPAPI) on Windows because `%APPDATA%` has no per-app sandbox. All other state stays in `LocalStore` JSON files.
- The app icon is pre-built at `assets/icon/app_icon.ico`; copy it to `windows/runner/resources/app_icon.ico` after `flutter create` (the template drops in a default Flutter icon).
- `tool/seed_demo_data.dart` derives its Windows default path from CompanyName/ProductName in `windows/runner/Runner.rc` — keep them in sync.

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

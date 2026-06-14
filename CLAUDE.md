# assignment_tracker_app — Claude guidance

Flutter port of the FastAPI dashboard at `../assignment-tracker/`. Targets iOS, Android, and Web.

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

`dio_cookie_manager` is a no-op on Web — browsers own cookies there. Use conditional imports (`lib/api/auth_transport_*.dart`): mobile uses `PersistCookieJar` + `flutter_secure_storage`; web uses `BrowserHttpClientAdapter()..withCredentials = true` and lets the browser persist.

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'screens/course_detail_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/fetch_status_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sign_off_form_screen.dart';
import 'screens/teacher_checkin_screen.dart';

GoRouter buildRouter({required String initialLocation}) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: '/', builder: (ctx, st) => const DashboardScreen()),
        GoRoute(
          path: '/course/:name',
          builder: (ctx, st) => CourseDetailScreen(
            courseName: Uri.decodeComponent(st.pathParameters['name'] ?? ''),
          ),
        ),
        GoRoute(
            path: '/settings', builder: (ctx, st) => const SettingsScreen()),
        GoRoute(
            path: '/fetch', builder: (ctx, st) => const FetchStatusScreen()),
        GoRoute(
            path: '/signoff', builder: (ctx, st) => const SignOffFormScreen()),
        GoRoute(
            path: '/teacher-checkin',
            builder: (ctx, st) => const TeacherCheckInScreen()),
      ],
    );

extension AppNav on BuildContext {
  /// Pops the current route so the transition plays backwards. Falls back to
  /// [fallback] when there is nothing to pop (e.g. the app was launched
  /// directly into this screen).
  void back(String fallback) {
    if (canPop()) {
      pop();
    } else {
      go(fallback);
    }
  }
}

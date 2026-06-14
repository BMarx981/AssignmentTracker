import 'package:go_router/go_router.dart';

import 'screens/course_detail_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/fetch_status_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sign_off_form_screen.dart';

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
      ],
    );

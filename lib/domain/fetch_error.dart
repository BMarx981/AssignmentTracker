import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:assignment_tracker_app/api/synergy_client.dart';

/// User-facing representation of a fetch failure.
///
/// We translate dart exceptions (DioException, SynergyAuthException, etc.)
/// into a small handful of categories the UI can render with a clear headline,
/// a "what to try" suggestion, and an optional technical details payload.
class FetchError {
  const FetchError({
    required this.kind,
    required this.headline,
    required this.body,
    required this.suggestions,
    required this.icon,
    this.technicalDetails,
  });

  final FetchErrorKind kind;
  final String headline;
  final String body;
  final List<String> suggestions;
  final IconData icon;
  final String? technicalDetails;

  /// Classify an exception thrown by `CanvasClient` or `SynergyClient` into a
  /// user-friendly `FetchError`. The `source` is the human-readable name of
  /// the service ("Synergy" / "Canvas") and shows up in the headline.
  factory FetchError.from(Object exception, StackTrace stack,
      {required String source}) {
    if (exception is SynergyAuthException) {
      return FetchError(
        kind: FetchErrorKind.auth,
        icon: Icons.lock_outline,
        headline: "Couldn't sign in to $source",
        body: exception.message,
        suggestions: const [
          'Double-check your username and password in Settings.',
          'Try signing in at the ParentVUE website to confirm the account works.',
          'If you recently changed your password, update it in Settings.',
        ],
        technicalDetails: _trace(
          exception,
          stack,
          diagnostics: exception.diagnostics,
          raw: exception.rawHtml,
        ),
      );
    }
    if (exception is DioException) {
      final status = exception.response?.statusCode;
      if (status == 401 || status == 403) {
        return FetchError(
          kind: FetchErrorKind.auth,
          icon: Icons.lock_outline,
          headline: "$source rejected your credentials",
          body:
              'The server returned HTTP $status. The token or password is no longer valid.',
          suggestions: [
            if (source == 'Canvas')
              'Generate a new Canvas access token and paste it into Settings.'
            else
              'Update your $source password in Settings.',
            'Confirm the base URL in Settings matches your school district.',
          ],
          technicalDetails: _trace(exception, stack),
        );
      }
      if (status != null && status >= 500) {
        return FetchError(
          kind: FetchErrorKind.server,
          icon: Icons.cloud_off_outlined,
          headline: '$source is having trouble',
          body:
              'The $source servers returned HTTP $status. This is on their end, not yours.',
          suggestions: [
            'Wait a few minutes and try again.',
            'Check whether the $source website is up in a browser.',
          ],
          technicalDetails: _trace(exception, stack),
        );
      }
      switch (exception.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return FetchError(
            kind: FetchErrorKind.network,
            icon: Icons.wifi_off_outlined,
            headline: 'The request to $source timed out',
            body:
                "We didn't hear back from $source in time. This usually means a slow connection.",
            suggestions: const [
              'Check your internet connection and try again.',
              'If you\'re on school Wi-Fi, the network may be blocking the request.',
            ],
            technicalDetails: _trace(exception, stack),
          );
        case DioExceptionType.connectionError:
        case DioExceptionType.unknown:
          return FetchError(
            kind: FetchErrorKind.network,
            icon: Icons.wifi_off_outlined,
            headline: "Couldn't reach $source",
            body:
                "We couldn't connect to $source. The network may be down or the base URL may be wrong.",
            suggestions: const [
              'Check your internet connection.',
              'Verify the base URL in Settings.',
            ],
            technicalDetails: _trace(exception, stack),
          );
        default:
          break;
      }
    }
    return FetchError(
      kind: FetchErrorKind.unknown,
      icon: Icons.error_outline,
      headline: 'Something went wrong fetching $source',
      body:
          "We hit an unexpected error. The technical details below will help us figure out what happened.",
      suggestions: const ['Try the fetch again.'],
      technicalDetails: _trace(exception, stack),
    );
  }

  static String _trace(
    Object e,
    StackTrace st, {
    String? diagnostics,
    String? raw,
  }) {
    final firstFrame = st.toString().split('\n').firstWhere(
          (l) => l.trim().isNotEmpty,
          orElse: () => '',
        );
    final buf = StringBuffer(e.toString());
    if (firstFrame.isNotEmpty) buf.write('\n$firstFrame');
    if (diagnostics != null && diagnostics.isNotEmpty) {
      buf.write('\n\n--- request trace ---\n');
      buf.write(diagnostics);
    }
    if (raw != null && raw.isNotEmpty) {
      buf.write('\n\n--- response snippet ---\n');
      buf.write(raw.length > 1500 ? '${raw.substring(0, 1500)}…' : raw);
    }
    return buf.toString();
  }
}

enum FetchErrorKind { auth, network, server, unknown }

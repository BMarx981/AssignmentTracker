import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Installs global error handlers and a copy-friendly error widget.
///
/// On Flutter Web the default red error screen is painted to canvas, so the
/// text can't be selected. This routes everything to the browser console and
/// swaps in a SelectableText-based widget so errors are copyable in-app too.
void installErrorLogging() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    developer.log(
      details.exceptionAsString(),
      name: 'FlutterError',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    developer.log(
      error.toString(),
      name: 'UncaughtAsync',
      error: error,
      stackTrace: stack,
    );
    return true;
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return _CopyableErrorWidget(details: details);
  };
}

/// Runs [body] inside a zone that forwards print() and uncaught zone errors
/// to the same logger. Call this from main() and put runApp() inside [body].
void runWithErrorLogging(void Function() body) {
  runZonedGuarded(
    body,
    (Object error, StackTrace stack) {
      developer.log(
        error.toString(),
        name: 'ZoneError',
        error: error,
        stackTrace: stack,
      );
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        parent.print(zone, line);
      },
    ),
  );
}

class _CopyableErrorWidget extends StatelessWidget {
  const _CopyableErrorWidget({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    final message =
        '${details.exceptionAsString()}\n\n${details.stack ?? ''}';
    // Reads platform brightness directly rather than Theme.of: this widget can
    // be built when the failing subtree has no Theme ancestor.
    final dark = MediaQuery.maybePlatformBrightnessOf(context) ==
        Brightness.dark;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: dark ? const Color(0xFF2A1616) : const Color(0xFFFFF3F3),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: SelectableText(
                message,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color:
                      dark ? const Color(0xFFFFB4AB) : const Color(0xFF8B0000),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

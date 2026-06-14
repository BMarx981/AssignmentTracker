import 'dart:io' show Platform, Process;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

/// Opens Gmail's web compose window prefilled with [to], [subject], and [body].
///
/// Prefers Chrome on desktop (macOS today, Windows when we add that target);
/// on iOS / Android we hand the URL to `url_launcher` and let the OS pick a
/// browser — that's almost always Chrome when it's installed, and Gmail's
/// web compose URL works fine in any modern browser.
///
/// Returns `true` if the launch was dispatched, `false` if no launcher
/// strategy succeeded.
Future<bool> openGmailCompose({
  required String to,
  required String subject,
  required String body,
}) async {
  final uri = Uri.https('mail.google.com', '/mail/', {
    'view': 'cm',
    'fs': '1',
    'to': to,
    'su': subject,
    'body': body,
  });

  if (!kIsWeb && Platform.isMacOS) {
    if (await _runProcess('open', ['-a', 'Google Chrome', uri.toString()])) {
      return true;
    }
    // Chrome missing? Fall back to the system default browser.
    return _runProcess('open', [uri.toString()]);
  }

  if (!kIsWeb && Platform.isWindows) {
    // `start "" chrome url` — the empty quoted arg is the window title that
    // `start` would otherwise eat. If Chrome isn't on PATH, fall through.
    if (await _runProcess(
        'cmd', ['/c', 'start', '', 'chrome', uri.toString()])) {
      return true;
    }
    return _runProcess('cmd', ['/c', 'start', '', uri.toString()]);
  }

  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<bool> _runProcess(String exe, List<String> args) async {
  try {
    final r = await Process.run(exe, args);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}

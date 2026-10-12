import 'package:intl/intl.dart';

/// What the app knows about the saved Canvas token's lifetime. Drives the
/// caption under the token field in Settings and the dashboard banner.
class CanvasTokenStatus {
  const CanvasTokenStatus({this.expiresAt, this.rejected = false});

  /// Built from Canvas's token record (`GET /users/self/tokens/:hint`).
  factory CanvasTokenStatus.fromJson(Map<String, dynamic> j) {
    final raw = j['expires_at'] as String?;
    return CanvasTokenStatus(
      expiresAt: raw == null ? null : DateTime.tryParse(raw),
    );
  }

  /// Start nagging this many days out. District tokens last 90 days, so two
  /// weeks is enough notice without the banner becoming wallpaper.
  static const warnDays = 14;

  /// Null when the token never expires.
  final DateTime? expiresAt;

  /// Canvas answered 401: the token is expired, revoked, or mistyped.
  final bool rejected;

  /// Calendar days from [now] to the expiry date, both taken as local dates.
  /// Negative once it has passed; null when the token never expires.
  int? daysLeft(DateTime now) {
    final e = expiresAt?.toLocal();
    if (e == null) return null;
    // UTC midnights so a DST shift can't shave a day off.
    return DateTime.utc(e.year, e.month, e.day)
        .difference(DateTime.utc(now.year, now.month, now.day))
        .inDays;
  }

  bool needsAttention(DateTime now) {
    if (rejected) return true;
    final d = daysLeft(now);
    return d != null && d <= warnDays;
  }

  /// "Expires Jan 10, 2027 (in 90 days)" and friends.
  String describe(DateTime now) {
    if (rejected) {
      return 'Canvas rejected this token. It has expired or been revoked.';
    }
    final d = daysLeft(now);
    if (d == null) return 'Never expires';
    final date = DateFormat('MMM d, y').format(expiresAt!.toLocal());
    if (d < 0) return 'Expired $date';
    if (d == 0) return 'Expires today ($date)';
    if (d == 1) return 'Expires tomorrow ($date)';
    return 'Expires $date (in $d days)';
  }
}

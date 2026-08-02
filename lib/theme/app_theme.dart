// Central color tokens for the app.
//
// Every surface/text/badge color used by the UI lives here as a semantic token
// so light and dark mode stay in sync. Widgets read them via
// `AppColors.of(context)` rather than hardcoding hex values.
//
// The light values are the original CSS palette ported from dashboard.html;
// the dark values are hand-tuned equivalents (deep tinted backgrounds with
// light-tinted foregrounds) that keep the same semantic meaning.

import 'package:flutter/material.dart';

/// A background/foreground pair for a chip, pill, or badge.
@immutable
class BadgeStyle {
  final Color background;
  final Color foreground;
  const BadgeStyle(this.background, this.foreground);
}

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.card,
    required this.cardSubtle,
    required this.border,
    required this.textStrong,
    required this.textBody,
    required this.textMuted,
    required this.textSecondary,
    required this.textFaint,
    required this.iconMuted,
    required this.chevron,
    required this.gradeHidden,
    required this.gradeBad,
    required this.gradeWarn,
    required this.gradeOk,
    required this.gradeNone,
    required this.tierHigh,
    required this.tierMedium,
    required this.tierLow,
    required this.tierRest,
    required this.danger,
    required this.success,
    required this.dueSoon,
    required this.zeroGraded,
    required this.halfCredit,
    required this.info,
    required this.inClass,
    required this.synergy,
    required this.canvas,
    required this.submitted,
    required this.neutralChip,
    required this.actionChip,
    required this.neutralPill,
    required this.dangerText,
    required this.dangerBodyText,
    required this.codeBackground,
    required this.codeForeground,
  });

  /// Card / panel background (was `Colors.white`).
  final Color card;

  /// Slightly recessed panel inside a card (comment threads).
  final Color cardSubtle;

  /// Hairline border around cards and panels.
  final Color border;

  final Color textStrong; // headings, item names
  final Color textBody; // default body copy
  final Color textMuted; // secondary copy
  final Color textSecondary; // captions
  final Color textFaint; // group labels, grade source
  final Color iconMuted; // eye toggle
  final Color chevron; // row affordance
  final Color gradeHidden; // the "•••" placeholder

  // Grade band accents.
  final Color gradeBad;
  final Color gradeWarn;
  final Color gradeOk;
  final Color gradeNone;

  // Priority list tier accents (top 3 / top 6 / top 10 / rest).
  final Color tierHigh;
  final Color tierMedium;
  final Color tierLow;
  final Color tierRest;

  // Badge palette.
  final BadgeStyle danger; // missing / overdue
  final BadgeStyle success; // upcoming, planned, complete-pending
  final BadgeStyle dueSoon; // due today / tomorrow
  final BadgeStyle zeroGraded;
  final BadgeStyle halfCredit;
  final BadgeStyle info; // not-yet-graded, awaiting grade
  final BadgeStyle inClass;
  final BadgeStyle synergy;
  final BadgeStyle canvas;
  final BadgeStyle submitted; // submitted-pending-feedback
  final BadgeStyle neutralChip; // unposted quick note
  final BadgeStyle actionChip; // "Plan date" / "Already done"
  final BadgeStyle neutralPill;

  /// Error headline / destructive accent on a plain background.
  final Color dangerText;

  /// Error body copy inside a [danger]-backed panel.
  final Color dangerBodyText;

  // Technical-details block (monospace on a near-black surface).
  final Color codeBackground;
  final Color codeForeground;

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? light;

  static const light = AppColors(
    card: Color(0xFFFFFFFF),
    cardSubtle: Color(0xFFF9FAFB),
    border: Color(0xFFE3E3E3),
    textStrong: Color(0xFF1A1A1A),
    textBody: Color(0xFF333333),
    textMuted: Color(0xFF555555),
    textSecondary: Color(0xFF666666),
    textFaint: Color(0xFF888888),
    iconMuted: Color(0xFFAAAAAA),
    chevron: Color(0xFFBBBBBB),
    gradeHidden: Color(0xFFCCCCCC),
    gradeBad: Color(0xFFB71C1C),
    gradeWarn: Color(0xFFC77700),
    gradeOk: Color(0xFF1F7A3A),
    gradeNone: Color(0xFF999999),
    tierHigh: Color(0xFFB71C1C),
    tierMedium: Color(0xFFC77700),
    tierLow: Color(0xFF2D6CDF),
    tierRest: Color(0xFF999999),
    danger: BadgeStyle(Color(0xFFFDE2E2), Color(0xFF8A1A1A)),
    success: BadgeStyle(Color(0xFFD1FAE5), Color(0xFF065F46)),
    dueSoon: BadgeStyle(Color(0xFFFFF3CD), Color(0xFF7C4A00)),
    zeroGraded: BadgeStyle(Color(0xFFFFE9C2), Color(0xFF7C4A00)),
    halfCredit: BadgeStyle(Color(0xFFFFEED1), Color(0xFF6E4B00)),
    info: BadgeStyle(Color(0xFFE1ECFF), Color(0xFF1B3F88)),
    inClass: BadgeStyle(Color(0xFFECE4FF), Color(0xFF4B2A86)),
    synergy: BadgeStyle(Color(0xFFE2F5E6), Color(0xFF1B5E29)),
    canvas: BadgeStyle(Color(0xFFE9EAFF), Color(0xFF2A2D83)),
    submitted: BadgeStyle(Color(0xFFDBEAFE), Color(0xFF1E40AF)),
    neutralChip: BadgeStyle(Color(0xFFF1F5F9), Color(0xFF334155)),
    actionChip: BadgeStyle(Color(0xFFE0E7FF), Color(0xFF1E3A8A)),
    neutralPill: BadgeStyle(Color(0xFFEEEEEE), Color(0xFF333333)),
    dangerText: Color(0xFF8A1A1A),
    dangerBodyText: Color(0xFF4A1818),
    codeBackground: Color(0xFF2A1010),
    codeForeground: Color(0xFFEFD9D9),
  );

  static const dark = AppColors(
    card: Color(0xFF1C1E24),
    cardSubtle: Color(0xFF16181D),
    border: Color(0xFF2E323A),
    textStrong: Color(0xFFECEDF1),
    textBody: Color(0xFFD5D7DE),
    textMuted: Color(0xFFB4B9C2),
    textSecondary: Color(0xFFA0A6B0),
    textFaint: Color(0xFF8B919B),
    iconMuted: Color(0xFF767C86),
    chevron: Color(0xFF636972),
    gradeHidden: Color(0xFF4A4F58),
    gradeBad: Color(0xFFFF8A80),
    gradeWarn: Color(0xFFFFB74D),
    gradeOk: Color(0xFF6FD08C),
    gradeNone: Color(0xFF9AA0AA),
    tierHigh: Color(0xFFFF8A80),
    tierMedium: Color(0xFFFFB74D),
    tierLow: Color(0xFF7BA7FF),
    tierRest: Color(0xFF858B95),
    danger: BadgeStyle(Color(0xFF3A1B1B), Color(0xFFFFB4AB)),
    success: BadgeStyle(Color(0xFF13352A), Color(0xFF7EE2B8)),
    dueSoon: BadgeStyle(Color(0xFF3A2E12), Color(0xFFF5CE7A)),
    zeroGraded: BadgeStyle(Color(0xFF3A2A12), Color(0xFFF2C078)),
    halfCredit: BadgeStyle(Color(0xFF352A12), Color(0xFFE8C589)),
    info: BadgeStyle(Color(0xFF1A2540), Color(0xFF9DBEFF)),
    inClass: BadgeStyle(Color(0xFF2A2140), Color(0xFFC7B2F5)),
    synergy: BadgeStyle(Color(0xFF16301D), Color(0xFF8FD8A2)),
    canvas: BadgeStyle(Color(0xFF1F2140), Color(0xFFB0B4FF)),
    submitted: BadgeStyle(Color(0xFF17243F), Color(0xFF9CC0FF)),
    neutralChip: BadgeStyle(Color(0xFF262A31), Color(0xFFC5CAD3)),
    actionChip: BadgeStyle(Color(0xFF232744), Color(0xFFB3C0FF)),
    neutralPill: BadgeStyle(Color(0xFF2A2E36), Color(0xFFD5D7DE)),
    dangerText: Color(0xFFFF9B90),
    dangerBodyText: Color(0xFFE8C3BE),
    codeBackground: Color(0xFF241313),
    codeForeground: Color(0xFFEFD9D9),
  );

  @override
  AppColors copyWith() => this;

  /// Snaps at the midpoint rather than interpolating ~35 tokens. The
  /// ColorScheme underneath still crossfades, so the swap reads as a fade.
  @override
  AppColors lerp(covariant ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return t < 0.5 ? this : other;
  }
}

ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Colors.indigo,
    brightness: Brightness.light,
  );
  return _base(scheme, AppColors.light, const Color(0xFFF6F7FB));
}

ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Colors.indigo,
    brightness: Brightness.dark,
  );
  return _base(scheme, AppColors.dark, const Color(0xFF121317));
}

ThemeData _base(ColorScheme scheme, AppColors colors, Color scaffold) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scaffold,
    canvasColor: scaffold,
    // Cards/sheets/menus all sit on the same elevated surface as our own
    // card token so nothing looks pasted on in dark mode.
    cardColor: colors.card,
    dialogTheme: DialogThemeData(backgroundColor: colors.card),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: colors.card),
    popupMenuTheme: PopupMenuThemeData(color: colors.card),
    dividerTheme: DividerThemeData(color: colors.border),
    appBarTheme: AppBarTheme(
      backgroundColor: scaffold,
      surfaceTintColor: Colors.transparent,
      foregroundColor: colors.textStrong,
      elevation: 0,
    ),
    extensions: [colors],
  );
}

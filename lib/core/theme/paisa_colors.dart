import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Theme extension carrying PaisaTrack's semantic money/status colors.
///
/// Widgets must read these through [PaisaColors.of] rather than hard-coding
/// `Colors.red`/`Colors.green`, so debit/credit/warning rendering stays
/// consistent and theme-aware across the app.
@immutable
class PaisaColors extends ThemeExtension<PaisaColors> {
  const PaisaColors({
    required this.credit,
    required this.debit,
    required this.warning,
    required this.gold,
    required this.info,
    // ── Bloom fields ──
    required this.violetPrimary,
    required this.violetDark,
    required this.inkPrimary,
    required this.inkSecondary,
    required this.inkTertiary,
    required this.inkQuaternary,
    required this.surfaceBase,
    required this.surfaceSunken,
    required this.surfaceCard,
    required this.surfaceChip,
    required this.hairline,
    required this.bloomCredit,
    required this.bloomDebit,
  });

  /// Money received. Amounts and direction indicators only — never row
  /// backgrounds (design-system.md §5).
  final Color credit;

  /// Money spent. Amounts and direction indicators only. Distinct from the
  /// theme's error color: a debit is normal, an error is a failure.
  final Color debit;

  /// Degraded/needs-attention states: needs_review chips, permission-denied
  /// notices, price-creep flags.
  final Color warning;

  /// Brand gold accent: achievement/insight highlights, sparingly.
  final Color gold;

  /// Informational accent (matches the blue illustration tiles).
  final Color info;

  // ── Bloom semantic fields ──

  /// Bloom primary action color (violet).
  final Color violetPrimary;

  /// Pressed/emphasis violet.
  final Color violetDark;

  /// Primary text / dark UI chrome.
  final Color inkPrimary;

  /// Body text.
  final Color inkSecondary;

  /// Captions and metadata.
  final Color inkTertiary;

  /// Disabled / inactive nav.
  final Color inkQuaternary;

  /// Screen background.
  final Color surfaceBase;

  /// Recessed settings / sort background.
  final Color surfaceSunken;

  /// Cards, rows.
  final Color surfaceCard;

  /// Unselected chips, icon button backgrounds.
  final Color surfaceChip;

  /// 1px dividers.
  final Color hairline;

  /// Money-in color (Bloom scheme).
  final Color bloomCredit;

  /// Money-out color (Bloom scheme).
  final Color bloomDebit;

  static const dark = PaisaColors(
    credit: AppColorTokens.creditDark,
    debit: AppColorTokens.debitDark,
    warning: AppColorTokens.warningDark,
    gold: AppColorTokens.gold,
    info: AppColorTokens.royalBlue,
    violetPrimary: AppColorTokens.violetPrimary,
    violetDark: AppColorTokens.violetPrimaryDark,
    inkPrimary: AppColorTokens.bloomDarkTextPrimary,
    inkSecondary: AppColorTokens.bloomDarkTextSecondary,
    inkTertiary: AppColorTokens.bloomDarkTextTertiary,
    inkQuaternary: AppColorTokens.inkQuaternary,
    surfaceBase: AppColorTokens.bloomDarkBase,
    surfaceSunken: AppColorTokens.bloomDarkBase,
    surfaceCard: AppColorTokens.bloomDarkCard,
    surfaceChip: AppColorTokens.bloomDarkCard,
    hairline: AppColorTokens.bloomDarkOutline,
    bloomCredit: AppColorTokens.bloomCreditDark,
    bloomDebit: AppColorTokens.bloomDebitDark,
  );

  static const light = PaisaColors(
    credit: AppColorTokens.creditLight,
    debit: AppColorTokens.debitLight,
    warning: AppColorTokens.warningLight,
    gold: AppColorTokens.gold,
    info: AppColorTokens.royalBlue,
    violetPrimary: AppColorTokens.violetPrimary,
    violetDark: AppColorTokens.violetPrimaryDark,
    inkPrimary: AppColorTokens.ink,
    inkSecondary: AppColorTokens.inkSecondary,
    inkTertiary: AppColorTokens.inkTertiary,
    inkQuaternary: AppColorTokens.inkQuaternary,
    surfaceBase: AppColorTokens.bloomBase,
    surfaceSunken: AppColorTokens.bloomSunken,
    surfaceCard: AppColorTokens.bloomCard,
    surfaceChip: AppColorTokens.bloomChip,
    hairline: AppColorTokens.bloomHairline,
    bloomCredit: AppColorTokens.bloomCreditLight,
    bloomDebit: AppColorTokens.bloomDebitLight,
  );

  /// Resolves the extension with a brightness-appropriate fallback so widgets
  /// keep working in tests that pump a bare [MaterialApp] without app themes.
  static PaisaColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<PaisaColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  PaisaColors copyWith({
    Color? credit,
    Color? debit,
    Color? warning,
    Color? gold,
    Color? info,
    Color? violetPrimary,
    Color? violetDark,
    Color? inkPrimary,
    Color? inkSecondary,
    Color? inkTertiary,
    Color? inkQuaternary,
    Color? surfaceBase,
    Color? surfaceSunken,
    Color? surfaceCard,
    Color? surfaceChip,
    Color? hairline,
    Color? bloomCredit,
    Color? bloomDebit,
  }) {
    return PaisaColors(
      credit: credit ?? this.credit,
      debit: debit ?? this.debit,
      warning: warning ?? this.warning,
      gold: gold ?? this.gold,
      info: info ?? this.info,
      violetPrimary: violetPrimary ?? this.violetPrimary,
      violetDark: violetDark ?? this.violetDark,
      inkPrimary: inkPrimary ?? this.inkPrimary,
      inkSecondary: inkSecondary ?? this.inkSecondary,
      inkTertiary: inkTertiary ?? this.inkTertiary,
      inkQuaternary: inkQuaternary ?? this.inkQuaternary,
      surfaceBase: surfaceBase ?? this.surfaceBase,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      surfaceCard: surfaceCard ?? this.surfaceCard,
      surfaceChip: surfaceChip ?? this.surfaceChip,
      hairline: hairline ?? this.hairline,
      bloomCredit: bloomCredit ?? this.bloomCredit,
      bloomDebit: bloomDebit ?? this.bloomDebit,
    );
  }

  @override
  PaisaColors lerp(ThemeExtension<PaisaColors>? other, double t) {
    if (other is! PaisaColors) return this;
    return PaisaColors(
      credit: Color.lerp(credit, other.credit, t)!,
      debit: Color.lerp(debit, other.debit, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      info: Color.lerp(info, other.info, t)!,
      violetPrimary: Color.lerp(violetPrimary, other.violetPrimary, t)!,
      violetDark: Color.lerp(violetDark, other.violetDark, t)!,
      inkPrimary: Color.lerp(inkPrimary, other.inkPrimary, t)!,
      inkSecondary: Color.lerp(inkSecondary, other.inkSecondary, t)!,
      inkTertiary: Color.lerp(inkTertiary, other.inkTertiary, t)!,
      inkQuaternary: Color.lerp(inkQuaternary, other.inkQuaternary, t)!,
      surfaceBase: Color.lerp(surfaceBase, other.surfaceBase, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      surfaceCard: Color.lerp(surfaceCard, other.surfaceCard, t)!,
      surfaceChip: Color.lerp(surfaceChip, other.surfaceChip, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      bloomCredit: Color.lerp(bloomCredit, other.bloomCredit, t)!,
      bloomDebit: Color.lerp(bloomDebit, other.bloomDebit, t)!,
    );
  }
}

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

  static const dark = PaisaColors(
    credit: AppColorTokens.creditDark,
    debit: AppColorTokens.debitDark,
    warning: AppColorTokens.warningDark,
    gold: AppColorTokens.gold,
    info: AppColorTokens.royalBlue,
  );

  static const light = PaisaColors(
    credit: AppColorTokens.creditLight,
    debit: AppColorTokens.debitLight,
    warning: AppColorTokens.warningLight,
    gold: AppColorTokens.gold,
    info: AppColorTokens.royalBlue,
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
  }) {
    return PaisaColors(
      credit: credit ?? this.credit,
      debit: debit ?? this.debit,
      warning: warning ?? this.warning,
      gold: gold ?? this.gold,
      info: info ?? this.info,
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
    );
  }
}

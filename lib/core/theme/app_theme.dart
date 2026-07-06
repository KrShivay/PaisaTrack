import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'paisa_colors.dart';

/// PaisaTrack Material 3 themes built from the tokens in `app_tokens.dart`.
///
/// Dark is the primary theme (brand anchor); light is a full derived variant.
/// Screens should never construct their own `ThemeData` — they consume these
/// via `MaterialApp(theme:, darkTheme:)` and read semantic colors through
/// [PaisaColors.of].
abstract final class AppTheme {
  /// Amounts must render with tabular (monospaced) digits so columns of
  /// figures align; apply to any [Text] showing money.
  static const tabularFigures = [FontFeature.tabularFigures()];

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColorTokens.emerald,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColorTokens.emeraldBright,
      onPrimary: AppColorTokens.darkBackground,
      secondary: AppColorTokens.gold,
      onSecondary: AppColorTokens.darkBackground,
      tertiary: AppColorTokens.royalBlue,
      surface: AppColorTokens.darkBackground,
      onSurface: AppColorTokens.darkTextPrimary,
      surfaceContainerLowest: AppColorTokens.darkBackground,
      surfaceContainerLow: AppColorTokens.darkSurface,
      surfaceContainer: AppColorTokens.darkSurface,
      surfaceContainerHigh: AppColorTokens.darkSurfaceRaised,
      surfaceContainerHighest: AppColorTokens.darkSurfaceRaised,
      onSurfaceVariant: AppColorTokens.darkTextSecondary,
      outline: AppColorTokens.darkOutline,
      outlineVariant: AppColorTokens.darkOutline,
      error: AppColorTokens.errorDark,
    );
    return _base(scheme, PaisaColors.dark);
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColorTokens.emerald,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColorTokens.creditLight,
      secondary: AppColorTokens.gold,
      tertiary: AppColorTokens.royalBlue,
      surface: AppColorTokens.lightBackground,
      onSurface: AppColorTokens.lightTextPrimary,
      surfaceContainerLowest: AppColorTokens.lightSurface,
      surfaceContainerLow: AppColorTokens.lightSurface,
      surfaceContainer: AppColorTokens.lightSurface,
      surfaceContainerHigh: AppColorTokens.lightSurfaceRaised,
      surfaceContainerHighest: AppColorTokens.lightSurfaceRaised,
      onSurfaceVariant: AppColorTokens.lightTextSecondary,
      outline: AppColorTokens.lightOutline,
      outlineVariant: AppColorTokens.lightOutline,
      error: AppColorTokens.errorLight,
    );
    return _base(scheme, PaisaColors.light);
  }

  static ThemeData _base(ColorScheme scheme, PaisaColors paisa) {
    final isDark = scheme.brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      extensions: [paisa],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor:
            isDark ? AppColorTokens.darkSurface : AppColorTokens.lightSurface,
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.18 : 0.14),
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52), // >=48dp touch target height
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    );
  }
}

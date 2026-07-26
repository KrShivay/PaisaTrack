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

  // ── Bloom font families ──
  static const bloomDisplayFamily = 'SpaceGrotesk';
  static const bloomMonoFamily = 'IBMPlexMono';

  /// Convenience factory for a Bloom display (Space Grotesk) text style.
  static TextStyle bloomDisplay(
    double size,
    FontWeight weight, {
    double letterSpacing = -0.02,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: bloomDisplayFamily,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: size * letterSpacing,
      color: color,
    );
  }

  /// Convenience factory for a Bloom monospace (IBM Plex Mono) text style.
  ///
  /// All rupee amounts, date numbers, percentages, and counters use this.
  static TextStyle bloomMono(
    double size,
    FontWeight weight, {
    double letterSpacing = -0.03,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: bloomMonoFamily,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: size * letterSpacing,
      fontFeatures: tabularFigures,
      color: color,
    );
  }

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

  // ── Bloom theme variants ──

  /// Bloom-branded light theme with Space Grotesk as the default font and
  /// the violet-first color scheme from the redesign handoff.
  static ThemeData bloomLight() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColorTokens.violetPrimary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColorTokens.violetPrimary,
      onPrimary: Colors.white,
      secondary: AppColorTokens.bloomEmerald,
      onSecondary: AppColorTokens.ink,
      tertiary: AppColorTokens.bloomGold,
      surface: AppColorTokens.bloomBase,
      onSurface: AppColorTokens.ink,
      surfaceContainerLowest: AppColorTokens.bloomBase,
      surfaceContainerLow: AppColorTokens.bloomCard,
      surfaceContainer: AppColorTokens.bloomCard,
      surfaceContainerHigh: AppColorTokens.bloomSunken,
      surfaceContainerHighest: AppColorTokens.bloomSunken,
      onSurfaceVariant: AppColorTokens.inkSecondary,
      outline: AppColorTokens.bloomHairline,
      outlineVariant: AppColorTokens.bloomHairline,
      error: AppColorTokens.bloomDebitLight,
    );
    return _bloomBase(scheme, PaisaColors.light);
  }

  /// Bloom-branded dark theme with the deep violet/ink surfaces.
  static ThemeData bloomDark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColorTokens.violetPrimary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColorTokens.violetPrimary,
      onPrimary: Colors.white,
      secondary: AppColorTokens.bloomEmerald,
      onSecondary: AppColorTokens.bloomDarkBase,
      tertiary: AppColorTokens.bloomGold,
      surface: AppColorTokens.bloomDarkBase,
      onSurface: AppColorTokens.bloomDarkTextPrimary,
      surfaceContainerLowest: AppColorTokens.bloomDarkBase,
      surfaceContainerLow: AppColorTokens.bloomDarkCard,
      surfaceContainer: AppColorTokens.bloomDarkCard,
      surfaceContainerHigh: AppColorTokens.bloomDarkCard,
      surfaceContainerHighest: AppColorTokens.bloomDarkCard,
      onSurfaceVariant: AppColorTokens.bloomDarkTextSecondary,
      outline: AppColorTokens.bloomDarkOutline,
      outlineVariant: AppColorTokens.bloomDarkOutline,
      error: AppColorTokens.bloomDebitDark,
    );
    return _bloomBase(scheme, PaisaColors.dark);
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
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isDark ? 0.6 : 0.8),
          ),
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
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.16),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
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

  /// Bloom-specific theme builder. Uses Space Grotesk as the default font,
  /// pill-shaped chips, larger sheet radii, and Bloom surface colors.
  static ThemeData _bloomBase(ColorScheme scheme, PaisaColors paisa) {
    final isDark = scheme.brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      fontFamily: bloomDisplayFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      extensions: [paisa],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: bloomDisplay(
          22,
          FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.bloomCard),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: AppSpacing.xs,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark
            ? AppColorTokens.bloomDarkOutline
            : AppColorTokens.bloomHairline,
        space: 1,
        thickness: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 54),
          backgroundColor: AppColorTokens.ink,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(27),
          ),
          textStyle: bloomDisplay(15, FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColorTokens.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.bloomRow),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.bloomChip),
        ),
        side: BorderSide.none,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor:
            isDark ? AppColorTokens.bloomDarkBase : AppColorTokens.bloomBase,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.bloomSheet),
          ),
        ),
      ),
    );
  }
}

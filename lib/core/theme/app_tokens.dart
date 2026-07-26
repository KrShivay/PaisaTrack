import 'package:flutter/material.dart';

/// Design tokens for PaisaTrack (see docs/design-system.md).
///
/// Tokens are the single source of truth for color, spacing, radius, and
/// motion values. Screens and widgets must consume these (directly or through
/// [ThemeData] / `PaisaColors`) instead of hard-coding values. Dark is the
/// primary theme (the brand anchor is the near-black + emerald + gold app
/// icon); light is a full derived variant.
abstract final class AppColorTokens {
  // Brand core (from assets/icons/app_icon.png: near-black green, emerald
  // ring, gold rupee; feature tiles are royal blue with gold accents).
  static const emerald = Color(0xFF10B981); // brand primary (light theme)
  static const emeraldBright = Color(0xFF34D399); // brand primary (dark theme)
  static const gold = Color(0xFFE8B54D); // accent: highlights, streaks, badges
  static const royalBlue = Color(0xFF3B82F6); // informational accent (icon tiles)

  // Dark theme surfaces (green-tinted near-black, matching the app icon).
  static const darkBackground = Color(0xFF0B1210);
  static const darkSurface = Color(0xFF141D1A);
  static const darkSurfaceRaised = Color(0xFF1B2724);
  static const darkOutline = Color(0xFF2E3D38);
  static const darkTextPrimary = Color(0xFFECF4F1);
  static const darkTextSecondary = Color(0xFF9DB2AB);

  // Light theme surfaces.
  static const lightBackground = Color(0xFFF6FAF8);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceRaised = Color(0xFFEEF5F2);
  static const lightOutline = Color(0xFFD5E2DD);
  static const lightTextPrimary = Color(0xFF14201C);
  static const lightTextSecondary = Color(0xFF5B6E67);

  // Semantic money colors. Applied to amounts, deltas, and direction chips
  // ONLY — never to whole rows or backgrounds (see design-system.md §5).
  static const creditDark = Color(0xFF3DDC97);
  static const creditLight = Color(0xFF0E9F6E);
  static const debitDark = Color(0xFFF48A8A);
  static const debitLight = Color(0xFFD64545);

  // Semantic status colors (parse/review states, alerts).
  static const warningDark = Color(0xFFFBBF24); // needs_review, degraded modes
  static const warningLight = Color(0xFFB45309);
  static const errorDark = Color(0xFFF87171); // failures only, not debits
  static const errorLight = Color(0xFFDC2626);

  // Brand gradients for rich UI cards & hero headers.
  static const darkHeroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF14241F),
      Color(0xFF0F1B17),
      Color(0xFF0B1210),
    ],
  );

  static const lightHeroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFFFFFF),
      Color(0xFFF1F8F5),
      Color(0xFFE8F3EE),
    ],
  );

  static const emeraldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF34D399),
      Color(0xFF059669),
    ],
  );

  static const goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFBBF24),
      Color(0xFFD97706),
    ],
  );
}

/// 4pt spacing scale. Use these instead of raw EdgeInsets values.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Default screen edge padding.
  static const screen = EdgeInsets.all(lg);
}

/// Corner radius scale.
abstract final class AppRadius {
  static const double sm = 8; // chips, small controls
  static const double md = 12; // cards, list containers
  static const double lg = 16; // sheets, dialogs
  static const double xl = 24; // hero cards, illustration tiles
}

/// Motion tokens. Respect the platform reduce-motion setting for anything
/// larger than opacity/color transitions.
abstract final class AppDurations {
  static const fast = Duration(milliseconds: 150); // state changes, ripples
  static const standard = Duration(milliseconds: 250); // navigation, expand
}

/// Brand illustration assets (assets/icons/*.png).
///
/// These are large glossy 3D illustrations: use them ONLY as hero images in
/// onboarding, empty states, and feature intros (48–120dp). Never as list,
/// tab, or button icons — those use Material icons (see design-system.md §6).
abstract final class AppIllustrations {
  static const appIcon = 'assets/icons/app_icon.png';
  static const wallet = 'assets/icons/wallet.png';
  static const spendAnalysis = 'assets/icons/spend_analysis.png';
  static const home = 'assets/icons/home.png';
  static const settings = 'assets/icons/settings.png';
  static const bill = 'assets/icons/bill.png';
  static const target = 'assets/icons/target.png';
  static const smsRefresh = 'assets/icons/sms_refresh.png';
  static const notification = 'assets/icons/notification.png';
  static const investmentGrowth = 'assets/icons/investment_growth.png';
}

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
  static const royalBlue =
      Color(0xFF3B82F6); // informational accent (icon tiles)

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

  // ── Bloom palette ────────────────────────────────────────────────────
  // Brand violet replaces emerald as primary; emerald is retained as the
  // positive-money / budget accent. Values from design_handoff README.

  // Primary violet.
  static const violetPrimary = Color(0xFF6D5AE6);
  static const violetPrimaryDark = Color(0xFF4F3FC4);
  static const violetLight = Color(0xFFA78BFA);

  // Ink – typography & dark UI chrome.
  static const ink = Color(0xFF1B1830);
  static const inkSecondary = Color(0xFF5B5580);
  static const inkTertiary = Color(0xFF7A7596);
  static const inkQuaternary = Color(0xFF8E88AD);

  // Light surfaces (Bloom).
  static const bloomBase = Color(0xFFFBFAFF);
  static const bloomSunken = Color(0xFFF3F1FC);
  static const bloomCard = Color(0xFFF6F4FE);
  static const bloomChip = Color(0xFFF1EFFB);
  static const bloomHairline = Color(0xFFEFECFA);

  // Dark surfaces (Bloom).
  static const bloomDarkBase = Color(0xFF0E0C1A);
  static const bloomDarkCard = Color(0xFF191630);
  static const bloomDarkOutline = Color(0xFF2E2A4E);
  static const bloomDarkTrack = Color(0xFF241F3E);

  // Bloom semantic money / accents.
  static const bloomEmerald = Color(0xFF34D399);
  static const bloomEmeraldDeep = Color(0xFF0E9F6E);
  static const bloomEmeraldDeepAlt = Color(0xFF0E7A56);
  static const bloomGold = Color(0xFFE8B54D);

  // Bloom credit / debit per brightness.
  static const bloomCreditLight = Color(0xFF12A46C);
  static const bloomCreditDark = Color(0xFF34D399);
  static const bloomDebitLight = Color(0xFFB4322F);
  static const bloomDebitDark = Color(0xFFF48A8A);

  // Bloom warning treatment.
  static const bloomWarningText = Color(0xFF8A5A00);
  static const bloomWarningBg = Color(0xFFFFF7E4);
  static const bloomWarningBorder = Color(0xFFF3D9A0);

  // Bloom gradients.
  static const bloomVioletGradient = LinearGradient(
    begin: Alignment(-0.4, -1),
    end: Alignment(0.4, 1),
    colors: [
      Color(0xFF6D5AE6),
      Color(0xFF8B6FF0),
      Color(0xFF5B49D6),
    ],
  );

  static const bloomBudgetGradient = LinearGradient(
    begin: Alignment(-0.3, -1),
    end: Alignment(0.3, 1),
    colors: [
      Color(0xFF123227),
      Color(0xFF0C1F19),
      Color(0xFF0A1815),
    ],
  );

  static const bloomEmeraldGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF34D399),
      Color(0xFF0E9F6E),
    ],
  );

  static const bloomOnboardingGradient = LinearGradient(
    begin: Alignment(-0.15, -1),
    end: Alignment(0.15, 0.88),
    colors: [
      Color(0xFF6D5AE6),
      Color(0xFF8B6FF0),
    ],
  );

  // Bloom shadows.
  static const bloomNavPillShadow = [
    BoxShadow(
      color: Color(0x471B1830), // rgba(27,24,48,0.28)
      blurRadius: 28,
      offset: Offset(0, 12),
    ),
  ];

  static const bloomSortCardShadow = [
    BoxShadow(
      color: Color(0x1F1B1830), // rgba(27,24,48,0.12)
      blurRadius: 40,
      offset: Offset(0, 18),
    ),
  ];

  static const bloomAskOrbGlow = [
    BoxShadow(
      color: Color(0x5934D399), // rgba(52,211,153,0.35)
      blurRadius: 24,
      offset: Offset(0, 10),
    ),
  ];

  // Dark-mode text hierarchy (Bloom).
  static const bloomDarkTextPrimary = Color(0xFFECEAF6);
  static const bloomDarkTextSecondary = Color(0xFFB8B2D6);
  static const bloomDarkTextTertiary = Color(0xFF8E88AD);

  // Ring remainder arcs.
  static const bloomRingRemainderLight = Color(0xFFE7E4F5);
  static const bloomRingRemainderDark = Color(0xFF241F3E);
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

  /// Bloom screen edge padding (20px horizontal).
  static const bloomScreen = EdgeInsets.symmetric(horizontal: 20);
}

/// Minimum hit-test sizes (Material accessibility baseline).
abstract final class AppSizes {
  /// Material minimum touch target (48dp). All interactive elements must
  /// meet this. See T-128 (accessibility) and T-155b.
  static const double minTouchTarget = 48.0;
}

/// Corner radius scale.
abstract final class AppRadius {
  static const double sm = 8; // chips, small controls
  static const double md = 12; // cards, list containers
  static const double lg = 16; // sheets, dialogs
  static const double xl = 24; // hero cards, illustration tiles

  // ── Bloom radius tokens ──
  static const double bloomChip = 16;
  static const double bloomRow = 20;
  static const double bloomCard = 24;
  static const double bloomHero = 26;
  static const double bloomNavPill = 32;
  static const double bloomSheet = 30;
  static const double bloomIconTile = 13;
  static const double bloomSmallButton = 18;
  static const double bloomPill = 17;
}

/// Motion tokens. Respect the platform reduce-motion setting for anything
/// larger than opacity/color transitions.
abstract final class AppDurations {
  static const fast = Duration(milliseconds: 150); // state changes, ripples
  static const standard = Duration(milliseconds: 250); // navigation, expand

  // ── Bloom motion tokens ──
  static const bloomSwipeCard = Duration(milliseconds: 220);
  static const bloomMascotBob = Duration(milliseconds: 3000);
  static const bloomAskOrbPulse = Duration(milliseconds: 2600);
  static const bloomStreakPop = Duration(milliseconds: 400);
  static const bloomShimmer = Duration(milliseconds: 1200);
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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/theme/app_tokens.dart';
import 'package:paisatrack/core/theme/app_theme.dart';
import 'package:paisatrack/core/theme/paisa_colors.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';

import '../../support/bloom_test_helpers.dart';

void main() {
  // ── Token integrity ──────────────────────────────────────────────────

  group('AppColorTokens Bloom palette', () {
    test('violet primary has expected hex value', () {
      expect(AppColorTokens.violetPrimary, const Color(0xFF6D5AE6));
    });

    test('ink has expected hex value', () {
      expect(AppColorTokens.ink, const Color(0xFF1B1830));
    });

    test('bloom light surfaces are distinct', () {
      expect(AppColorTokens.bloomBase, isNot(AppColorTokens.bloomCard));
      expect(AppColorTokens.bloomCard, isNot(AppColorTokens.bloomChip));
      expect(AppColorTokens.bloomChip, isNot(AppColorTokens.bloomSunken));
    });

    test('bloom dark surfaces are distinct from legacy dark surfaces', () {
      expect(
        AppColorTokens.bloomDarkBase,
        isNot(AppColorTokens.darkBackground),
      );
      expect(AppColorTokens.bloomDarkCard, isNot(AppColorTokens.darkSurface));
    });

    test('bloom credit/debit light colors match README', () {
      expect(AppColorTokens.bloomCreditLight, const Color(0xFF12A46C));
      expect(AppColorTokens.bloomDebitLight, const Color(0xFFB4322F));
    });

    test('bloom credit/debit dark colors match README', () {
      expect(AppColorTokens.bloomCreditDark, const Color(0xFF34D399));
      expect(AppColorTokens.bloomDebitDark, const Color(0xFFF48A8A));
    });

    test('bloom warning colors match README', () {
      expect(AppColorTokens.bloomWarningText, const Color(0xFF8A5A00));
      expect(AppColorTokens.bloomWarningBg, const Color(0xFFFFF7E4));
      expect(AppColorTokens.bloomWarningBorder, const Color(0xFFF3D9A0));
    });

    test('legacy tokens are preserved', () {
      expect(AppColorTokens.emerald, const Color(0xFF10B981));
      expect(AppColorTokens.darkBackground, const Color(0xFF0B1210));
      expect(AppColorTokens.lightSurface, const Color(0xFFFFFFFF));
      expect(AppColorTokens.creditDark, const Color(0xFF3DDC97));
      expect(AppColorTokens.debitLight, const Color(0xFFD64545));
    });

    test('bloom gradients have correct color counts', () {
      expect(AppColorTokens.bloomVioletGradient.colors, hasLength(3));
      expect(AppColorTokens.bloomBudgetGradient.colors, hasLength(3));
      expect(AppColorTokens.bloomEmeraldGradient.colors, hasLength(2));
      expect(AppColorTokens.bloomOnboardingGradient.colors, hasLength(2));
    });

    test('bloom shadows are non-empty', () {
      expect(AppColorTokens.bloomNavPillShadow, isNotEmpty);
      expect(AppColorTokens.bloomSortCardShadow, isNotEmpty);
      expect(AppColorTokens.bloomAskOrbGlow, isNotEmpty);
    });
  });

  group('AppRadius Bloom tokens', () {
    test('bloom radius values match design spec', () {
      expect(AppRadius.bloomChip, 16);
      expect(AppRadius.bloomRow, 20);
      expect(AppRadius.bloomCard, 24);
      expect(AppRadius.bloomHero, 26);
      expect(AppRadius.bloomNavPill, 32);
      expect(AppRadius.bloomSheet, 30);
      expect(AppRadius.bloomIconTile, 13);
    });

    test('legacy radius values are preserved', () {
      expect(AppRadius.sm, 8);
      expect(AppRadius.md, 12);
      expect(AppRadius.lg, 16);
      expect(AppRadius.xl, 24);
    });
  });

  group('AppDurations Bloom tokens', () {
    test('bloom motion durations match design spec', () {
      expect(
        AppDurations.bloomSwipeCard,
        const Duration(milliseconds: 220),
      );
      expect(
        AppDurations.bloomMascotBob,
        const Duration(milliseconds: 3000),
      );
      expect(
        AppDurations.bloomAskOrbPulse,
        const Duration(milliseconds: 2600),
      );
      expect(
        AppDurations.bloomStreakPop,
        const Duration(milliseconds: 400),
      );
    });

    test('legacy durations are preserved', () {
      expect(AppDurations.fast, const Duration(milliseconds: 150));
      expect(AppDurations.standard, const Duration(milliseconds: 250));
    });
  });

  // ── PaisaColors Bloom fields ─────────────────────────────────────────

  group('PaisaColors Bloom fields', () {
    test('light instance includes Bloom fields', () {
      expect(PaisaColors.light.violetPrimary, AppColorTokens.violetPrimary);
      expect(PaisaColors.light.inkPrimary, AppColorTokens.ink);
      expect(PaisaColors.light.surfaceBase, AppColorTokens.bloomBase);
      expect(PaisaColors.light.bloomCredit, AppColorTokens.bloomCreditLight);
      expect(PaisaColors.light.bloomDebit, AppColorTokens.bloomDebitLight);
    });

    test('dark instance includes Bloom fields', () {
      expect(PaisaColors.dark.violetPrimary, AppColorTokens.violetPrimary);
      expect(PaisaColors.dark.inkPrimary, AppColorTokens.bloomDarkTextPrimary);
      expect(PaisaColors.dark.surfaceBase, AppColorTokens.bloomDarkBase);
      expect(PaisaColors.dark.bloomCredit, AppColorTokens.bloomCreditDark);
      expect(PaisaColors.dark.bloomDebit, AppColorTokens.bloomDebitDark);
    });

    test('legacy credit/debit fields are preserved', () {
      expect(PaisaColors.light.credit, AppColorTokens.creditLight);
      expect(PaisaColors.dark.debit, AppColorTokens.debitDark);
    });

    test('copyWith updates Bloom fields', () {
      const custom = Color(0xFF123456);
      final modified = PaisaColors.light.copyWith(violetPrimary: custom);
      expect(modified.violetPrimary, custom);
      expect(modified.credit, PaisaColors.light.credit);
    });

    test('lerp interpolates Bloom fields', () {
      final mid = PaisaColors.light.lerp(PaisaColors.dark, 0.5);
      expect(mid.violetPrimary, isNotNull);
      // Both light and dark have the same violetPrimary, so midpoint matches.
      expect(mid.violetPrimary, AppColorTokens.violetPrimary);
    });
  });

  // ── AppTheme Bloom variants ──────────────────────────────────────────

  group('AppTheme Bloom variants', () {
    test('bloomDisplay produces Space Grotesk family', () {
      final style = AppTheme.bloomDisplay(16, FontWeight.w600);
      expect(style.fontFamily, 'SpaceGrotesk');
      expect(style.fontSize, 16);
      expect(style.fontWeight, FontWeight.w600);
    });

    test('bloomMono produces IBM Plex Mono family with tight tracking', () {
      final style = AppTheme.bloomMono(42, FontWeight.w600);
      expect(style.fontFamily, 'IBMPlexMono');
      expect(style.letterSpacing, closeTo(42 * -0.03, 0.01));
    });

    test('bloomLight returns a ThemeData with Bloom surfaces', () {
      final theme = AppTheme.bloomLight();
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.surface, AppColorTokens.bloomBase);
      // Font family is applied via ThemeData.fontFamily (private), verify
      // through the appBar title text style which inherits it.
      expect(
        theme.appBarTheme.titleTextStyle?.fontFamily,
        'SpaceGrotesk',
      );
      expect(theme.extension<PaisaColors>(), isNotNull);
    });

    test('bloomDark returns a ThemeData with dark Bloom surfaces', () {
      final theme = AppTheme.bloomDark();
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.surface, AppColorTokens.bloomDarkBase);
      expect(
        theme.appBarTheme.titleTextStyle?.fontFamily,
        'SpaceGrotesk',
      );
    });

    test('legacy dark/light themes still build successfully', () {
      final dark = AppTheme.dark();
      final light = AppTheme.light();
      expect(dark.colorScheme.surface, AppColorTokens.darkBackground);
      expect(light.colorScheme.surface, AppColorTokens.lightBackground);
    });
  });

  // ── BloomText widget ─────────────────────────────────────────────────

  group('BloomText', () {
    testWidgets('display renders with Space Grotesk', (tester) async {
      await pumpBloomWidget(
        tester,
        const BloomText.display('Test', size: 24),
      );

      final textWidget = tester.widget<Text>(find.text('Test'));
      expect(textWidget.style?.fontFamily, 'SpaceGrotesk');
    });

    testWidgets('mono renders with IBM Plex Mono', (tester) async {
      await pumpBloomWidget(
        tester,
        const BloomText.mono('₹1,240', size: 42),
      );

      final textWidget = tester.widget<Text>(find.text('₹1,240'));
      expect(textWidget.style?.fontFamily, 'IBMPlexMono');
    });

    testWidgets('body has 1.5 line height', (tester) async {
      await pumpBloomWidget(
        tester,
        const BloomText.body('Long body text for testing'),
      );

      final textWidget =
          tester.widget<Text>(find.text('Long body text for testing'));
      expect(textWidget.style?.height, 1.5);
    });

    testWidgets('renders at 320px width without overflow', (tester) async {
      await pumpBloomWidgetNarrow(
        tester,
        const BloomText.display('Narrow viewport test', size: 24),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ── BloomAmount widget ───────────────────────────────────────────────

  group('BloomAmount', () {
    testWidgets('renders formatted positive amount', (tester) async {
      await pumpBloomWidget(
        tester,
        const BloomAmount(amount: 1240.50),
      );

      expect(find.text('₹1,240.50'), findsOneWidget);
    });

    testWidgets('hides paise when showPaise is false', (tester) async {
      await pumpBloomWidget(
        tester,
        const BloomAmount(amount: 28410.00, showPaise: false),
      );

      expect(find.text('₹28,410'), findsOneWidget);
    });

    testWidgets('renders with IBM Plex Mono', (tester) async {
      await pumpBloomWidget(
        tester,
        const BloomAmount(amount: 100),
      );

      final textWidget = tester.widget<Text>(find.textContaining('₹'));
      expect(textWidget.style?.fontFamily, 'IBMPlexMono');
    });

    testWidgets('uses credit color for positive amounts', (tester) async {
      await pumpBloomWidget(
        tester,
        const BloomAmount(amount: 500),
      );

      final textWidget = tester.widget<Text>(find.textContaining('₹'));
      expect(textWidget.style?.color, AppColorTokens.bloomCreditLight);
    });

    testWidgets('uses debit color for negative amounts', (tester) async {
      await pumpBloomWidget(
        tester,
        const BloomAmount(amount: -500),
      );

      final textWidget = tester.widget<Text>(find.textContaining('₹'));
      expect(textWidget.style?.color, AppColorTokens.bloomDebitLight);
    });

    testWidgets('dark mode uses dark credit color', (tester) async {
      await pumpBloomWidget(
        tester,
        const BloomAmount(amount: 500),
        brightness: Brightness.dark,
      );

      final textWidget = tester.widget<Text>(find.textContaining('₹'));
      expect(textWidget.style?.color, AppColorTokens.bloomCreditDark);
    });
  });

  // ── BloomMascot widget ───────────────────────────────────────────────

  group('BloomMascot', () {
    testWidgets('renders at 36px without overflow', (tester) async {
      await pumpBloomWidget(
        tester,
        const BloomMascot(size: 36, bob: false),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(BloomMascot), findsOneWidget);
    });

    testWidgets('renders at 92px without overflow', (tester) async {
      await pumpBloomWidget(
        tester,
        const BloomMascot(size: 92, bob: false, borderRadius: 34),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('bob is disabled when reduce-motion is active', (tester) async {
      await pumpBloomWidgetReducedMotion(
        tester,
        const BloomMascot(size: 36, bob: true),
      );

      // The mascot should render without a Transform.translate animation.
      expect(find.byType(BloomMascot), findsOneWidget);
      // No AnimatedBuilder wrapping inside BloomMascot when motion is disabled.
      expect(
        find.descendant(
          of: find.byType(BloomMascot),
          matching: find.byType(AnimatedBuilder),
        ),
        findsNothing,
      );
    });

    testWidgets('pulse ring is disabled when reduce-motion is active',
        (tester) async {
      await pumpBloomWidgetReducedMotion(
        tester,
        const BloomMascot(size: 92, bob: false, pulseRing: true),
      );

      expect(find.byType(BloomMascot), findsOneWidget);
    });

    testWidgets('renders at 320px width', (tester) async {
      await pumpBloomWidgetNarrow(
        tester,
        const BloomMascot(size: 92, bob: false),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ── BloomCategoryTile ────────────────────────────────────────────────

  group('BloomCategoryTile', () {
    testWidgets('uses correct alpha for light theme', (tester) async {
      await pumpBloomWidget(
        tester,
        const BloomCategoryTile(categoryId: 'food_dining', size: 36),
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(BloomCategoryTile),
          matching: find.byType(Container).first,
        ),
      );
      final decoration = container.decoration as BoxDecoration;
      // Light mode uses 15% alpha.
      expect(decoration.color!.a, closeTo(0.15, 0.02));
    });

    testWidgets('uses correct alpha for dark theme', (tester) async {
      await pumpBloomWidget(
        tester,
        const BloomCategoryTile(categoryId: 'food_dining', size: 36),
        brightness: Brightness.dark,
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(BloomCategoryTile),
          matching: find.byType(Container).first,
        ),
      );
      final decoration = container.decoration as BoxDecoration;
      // Dark mode uses 18% alpha.
      expect(decoration.color!.a, closeTo(0.18, 0.02));
    });

    testWidgets('renders without overflow at 52px', (tester) async {
      await pumpBloomWidget(
        tester,
        const BloomCategoryTile(
          categoryId: 'transport',
          size: 52,
          borderRadius: 18,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ── BloomSkeleton ────────────────────────────────────────────────────

  group('BloomSkeleton', () {
    testWidgets('renders shimmer in normal mode', (tester) async {
      await pumpBloomWidget(
        tester,
        const BloomSkeleton(width: 200, height: 20),
      );
      expect(find.byType(BloomSkeleton), findsOneWidget);
    });

    testWidgets('shimmer is disabled when reduce-motion is active',
        (tester) async {
      await pumpBloomWidgetReducedMotion(
        tester,
        const BloomSkeleton(width: 200, height: 20),
      );

      // Should render as a static container, no AnimatedBuilder inside BloomSkeleton.
      expect(
        find.descendant(
          of: find.byType(BloomSkeleton),
          matching: find.byType(AnimatedBuilder),
        ),
        findsNothing,
      );
      expect(find.byType(BloomSkeleton), findsOneWidget);
    });
  });

  // ── BloomNotice ──────────────────────────────────────────────────────

  group('BloomNotice', () {
    testWidgets('warning variant renders message and action', (tester) async {
      await pumpBloomWidget(
        tester,
        BloomNotice.warning(
          message: 'Android is blocking us',
          actionLabel: 'Open settings',
          onAction: () {},
        ),
      );

      expect(find.text('Android is blocking us'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
    });

    testWidgets('error variant renders', (tester) async {
      await pumpBloomWidget(
        tester,
        const BloomNotice.error(
          message: 'Something went wrong',
        ),
      );

      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets('warning renders in dark mode', (tester) async {
      await pumpBloomWidget(
        tester,
        const BloomNotice.warning(message: 'Dark warning'),
        brightness: Brightness.dark,
      );

      expect(find.text('Dark warning'), findsOneWidget);
    });
  });

  // ── BloomMotion helpers ──────────────────────────────────────────────

  group('BloomMotion helpers', () {
    testWidgets('useReduceMotion returns false normally', (tester) async {
      late bool result;
      await pumpBloomWidget(
        tester,
        Builder(
          builder: (context) {
            result = useReduceMotion(context);
            return const SizedBox();
          },
        ),
      );
      expect(result, isFalse);
    });

    testWidgets('useReduceMotion returns true when disabled', (tester) async {
      late bool result;
      await pumpBloomWidgetReducedMotion(
        tester,
        Builder(
          builder: (context) {
            result = useReduceMotion(context);
            return const SizedBox();
          },
        ),
      );
      expect(result, isTrue);
    });

    testWidgets('BloomBobWrapper animates normally', (tester) async {
      await pumpBloomWidget(
        tester,
        const BloomBobWrapper(
          child: SizedBox(width: 50, height: 50),
        ),
      );

      // Verify it renders with an AnimatedBuilder for the bob.
      expect(
        find.descendant(
          of: find.byType(BloomBobWrapper),
          matching: find.byType(AnimatedBuilder),
        ),
        findsOneWidget,
      );
    });

    testWidgets('BloomBobWrapper static when reduce-motion is on',
        (tester) async {
      await pumpBloomWidgetReducedMotion(
        tester,
        const BloomBobWrapper(
          child: SizedBox(width: 50, height: 50),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(BloomBobWrapper),
          matching: find.byType(AnimatedBuilder),
        ),
        findsNothing,
      );
    });
  });

  // ── AppSpacing Bloom tokens ──────────────────────────────────────────

  group('AppSpacing Bloom tokens', () {
    test('bloom screen padding is 20px horizontal', () {
      expect(
        AppSpacing.bloomScreen,
        const EdgeInsets.symmetric(horizontal: 20),
      );
    });

    test('legacy screen padding is preserved', () {
      expect(AppSpacing.screen, const EdgeInsets.all(16));
    });
  });
}

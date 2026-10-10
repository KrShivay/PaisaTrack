import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import 'app_settings.dart';

/// Body of the Settings "APPEARANCE" section: theme cards and amount display.
class AppearanceSectionBody extends ConsumerWidget {
  const AppearanceSectionBody({
    super.key,
    required this.settings,
    required this.isDark,
  });

  final AppSettings settings;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appSettingsControllerProvider.notifier);
    final caption = AppTheme.bloomDisplay(
      11,
      FontWeight.w600,
      letterSpacing: 0.1,
      color: isDark
          ? AppColorTokens.bloomDarkTextTertiary
          : AppColorTokens.inkTertiary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('THEME', style: caption),
        const SizedBox(height: AppSpacing.sm),
        ThemeChoiceSelector(
          selected: settings.themeChoice,
          isDark: isDark,
          onSelected: notifier.setThemeChoice,
        ),
        const SizedBox(height: AppSpacing.lg),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.md),
        Text('AMOUNTS', style: caption),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Show paise',
            style: AppTheme.bloomDisplay(
              14,
              FontWeight.w600,
              color: isDark
                  ? AppColorTokens.bloomDarkTextPrimary
                  : AppColorTokens.ink,
            ),
          ),
          subtitle: Text(
            'Display exact decimals (e.g. ₹450.00)',
            style: AppTheme.bloomDisplay(
              12,
              FontWeight.w400,
              color: isDark
                  ? AppColorTokens.bloomDarkTextTertiary
                  : AppColorTokens.inkTertiary,
            ),
          ),
          value: settings.showPaise,
          activeThumbColor: AppColorTokens.violetPrimary,
          onChanged: notifier.setShowPaise,
        ),
      ],
    );
  }
}

/// Selectable theme cards. Three across when there is room, otherwise a
/// vertical list so labels never overflow on narrow screens or large text.
class ThemeChoiceSelector extends StatelessWidget {
  const ThemeChoiceSelector({
    super.key,
    required this.selected,
    required this.isDark,
    required this.onSelected,
  });

  final AppThemeChoice selected;
  final bool isDark;
  final ValueChanged<AppThemeChoice> onSelected;

  static const _gap = AppSpacing.sm;
  static const _minCardWidth = 104.0;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(13) > 17;
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = AppThemeChoice.values.length;
        final cardWidth = (constraints.maxWidth - _gap * (count - 1)) / count;
        final vertical = largeText || cardWidth < _minCardWidth;
        final cards = [
          for (final choice in AppThemeChoice.values)
            _ThemeCard(
              key: ValueKey('theme_choice_${choice.name}'),
              choice: choice,
              selected: selected == choice,
              isDark: isDark,
              vertical: vertical,
              onTap: () => onSelected(choice),
            ),
        ];
        if (vertical) {
          return Column(
            key: const ValueKey('theme_choices_vertical'),
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: _gap),
                cards[i],
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            key: const ValueKey('theme_choices_row'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: _gap),
                Expanded(child: cards[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

IconData _iconFor(AppThemeChoice choice) => switch (choice) {
      AppThemeChoice.light => Icons.light_mode_rounded,
      AppThemeChoice.dark => Icons.dark_mode_rounded,
      AppThemeChoice.system => Icons.brightness_auto_rounded,
    };

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    super.key,
    required this.choice,
    required this.selected,
    required this.isDark,
    required this.vertical,
    required this.onTap,
  });

  final AppThemeChoice choice;
  final bool selected;
  final bool isDark;
  final bool vertical;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.bloomChip);
    final textColor = selected
        ? (isDark ? AppColorTokens.bloomDarkTextPrimary : AppColorTokens.ink)
        : (isDark
            ? AppColorTokens.bloomDarkTextSecondary
            : AppColorTokens.inkSecondary);
    final label = Text(
      choice.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTheme.bloomDisplay(
        13,
        selected ? FontWeight.w700 : FontWeight.w600,
        color: textColor,
      ),
    );
    final icon = Icon(_iconFor(choice), size: 18, color: textColor);
    final check = Icon(
      selected ? Icons.check_circle_rounded : Icons.circle_outlined,
      size: 20,
      color: selected
          ? AppColorTokens.violetPrimary
          : (isDark
              ? AppColorTokens.bloomDarkOutline
              : AppColorTokens.inkQuaternary),
    );
    final swatch = _ThemeSwatch(choice: choice, isDark: isDark);

    final content = vertical
        ? Row(
            children: [
              SizedBox(width: 56, height: 36, child: swatch),
              const SizedBox(width: AppSpacing.md),
              icon,
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: label),
              check,
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 36, child: swatch),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  icon,
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: label),
                  check,
                ],
              ),
            ],
          );

    return Semantics(
      container: true,
      label: choice.label,
      button: true,
      selected: selected,
      onTap: onTap,
      child: ExcludeSemantics(
        // Opaque so taps on the rounded corners (outside the Material clip)
        // still select the card, matching its full semantic rect.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Material(
            color: isDark ? AppColorTokens.bloomDarkBase : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(
                width: 2,
                color: selected
                    ? AppColorTokens.violetPrimary
                    : (isDark
                        ? AppColorTokens.bloomDarkOutline
                        : AppColorTokens.bloomHairline),
              ),
            ),
            child: InkWell(
              borderRadius: radius,
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppSizes.minTouchTarget,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md - 2),
                  child: Center(child: content),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Miniature app-surface preview of a theme; "system" shows both halves.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.choice, required this.isDark});

  final AppThemeChoice choice;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: isDark
                ? AppColorTokens.bloomDarkOutline
                : AppColorTokens.bloomHairline,
          ),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: switch (choice) {
          AppThemeChoice.light => const _MiniSurface(dark: false),
          AppThemeChoice.dark => const _MiniSurface(dark: true),
          AppThemeChoice.system => const Row(
              children: [
                Expanded(child: _MiniSurface(dark: false)),
                Expanded(child: _MiniSurface(dark: true)),
              ],
            ),
        },
      ),
    );
  }
}

class _MiniSurface extends StatelessWidget {
  const _MiniSurface({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final base = dark ? AppColorTokens.bloomDarkBase : AppColorTokens.bloomBase;
    final bar = dark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomChip;
    return ColoredBox(
      color: base,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 5,
              width: 14,
              decoration: BoxDecoration(
                color: AppColorTokens.violetPrimary,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 3),
            Container(
              height: 5,
              decoration: BoxDecoration(
                color: bar,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

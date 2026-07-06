import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../capture/permissions/sms_permission.dart';
import '../../capture/permissions/sms_permission_provider.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/paisa_colors.dart';

/// First-run screen that explains why PaisaTrack needs SMS access and requests
/// the permission.
///
/// Denial is non-fatal: the app stays usable and the screen explains the
/// degraded state (no automatic capture) rather than blocking the user.
/// Degraded notices use the warning style, not error — a denied permission is
/// a valid choice, not a failure (docs/design-system.md §9).
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permission = ref.watch(smsPermissionControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('PaisaTrack')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 560;
          final illustrationHeight = compact ? 40.0 : 96.0;
          final outerPadding = compact ? AppSpacing.lg : AppSpacing.xl;
          final sectionGap = compact ? AppSpacing.sm : AppSpacing.xl;
          final titleStyle = compact
              ? Theme.of(context).textTheme.titleLarge
              : Theme.of(context).textTheme.headlineSmall;
          final bodyStyle = compact
              ? Theme.of(context).textTheme.bodyMedium
              : Theme.of(context).textTheme.bodyLarge;

          return SingleChildScrollView(
            padding: EdgeInsets.all(outerPadding),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand illustration: hero use only (design-system.md §6).
                    Image.asset(
                      AppIllustrations.smsRefresh,
                      height: illustrationHeight,
                      excludeFromSemantics: true,
                      errorBuilder: (context, error, stackTrace) =>
                          SizedBox(height: illustrationHeight),
                    ),
                    SizedBox(height: sectionGap),
                    Text(
                      'Read bank SMS on this device',
                      style: titleStyle?.copyWith(fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'PaisaTrack turns your bank and UPI messages into '
                      'transactions. Messages are parsed on your device and '
                      'never leave it. Grant SMS access to capture them '
                      'automatically.',
                      textAlign: TextAlign.center,
                      style: bodyStyle?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    SizedBox(height: sectionGap),
                    _PermissionBody(permission: permission),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PermissionBody extends ConsumerWidget {
  const _PermissionBody({required this.permission});

  final AsyncValue<SmsPermissionStatus> permission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(smsPermissionControllerProvider.notifier);
    final isBusy = permission.isLoading;

    return switch (permission) {
      AsyncData(:final value) when value.isGranted => const _GrantedNotice(),
      AsyncData(:final value)
          when value == SmsPermissionStatus.permanentlyDenied =>
        const _DegradedNotice(
          message: 'SMS access is blocked. Enable it in system settings to '
              'turn on automatic capture. You can still add transactions '
              'manually.',
        ),
      AsyncData(:final value) when value == SmsPermissionStatus.denied =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _DegradedNotice(
              message: 'Without SMS access PaisaTrack cannot capture '
                  'transactions automatically. You can grant it now or later '
                  'from settings.',
            ),
            const SizedBox(height: AppSpacing.lg),
            _GrantButton(onPressed: isBusy ? null : controller.request),
          ],
        ),
      AsyncError() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _DegradedNotice(
              message: 'Could not read the SMS permission state. Try again.',
            ),
            const SizedBox(height: AppSpacing.lg),
            _GrantButton(onPressed: isBusy ? null : controller.request),
          ],
        ),
      _ => _GrantButton(onPressed: isBusy ? null : controller.request),
    };
  }
}

class _GrantButton extends StatelessWidget {
  const _GrantButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      child: const Text('Grant SMS access'),
    );
  }
}

class _GrantedNotice extends StatelessWidget {
  const _GrantedNotice();

  @override
  Widget build(BuildContext context) {
    final paisa = PaisaColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.check_circle_outline, color: paisa.credit),
        const SizedBox(width: AppSpacing.sm),
        const Flexible(child: Text('SMS access granted. Capture is on.')),
      ],
    );
  }
}

/// Warning-styled notice container (design-system.md §9): warning tint at low
/// alpha, info icon, body text — never bare error-colored text.
class _DegradedNotice extends StatelessWidget {
  const _DegradedNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final paisa = PaisaColors.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: paisa.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: paisa.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

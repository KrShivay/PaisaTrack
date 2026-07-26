import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../capture/permissions/sms_permission.dart';
import '../../capture/permissions/sms_permission_provider.dart';
import '../../capture/sms_backfill.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/bloom/bloom.dart';

/// First-run Bloom onboarding screen that requests SMS permission honestly and
/// transparently in a single screen.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permission = ref.watch(smsPermissionControllerProvider);
    final backfillStatus = ref.watch(smsBackfillStatusProvider);

    return Scaffold(
      backgroundColor: AppColorTokens.bloomBase,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxHeight < 680;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                children: [
                  // Top violet gradient block (~44% height)
                  _TopHeroBlock(isCompact: isCompact),
                  // Bottom light section with benefit rows, progress, and CTA
                  _BottomContentBlock(
                    permission: permission,
                    backfillStatus: backfillStatus,
                    isCompact: isCompact,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TopHeroBlock extends StatelessWidget {
  const _TopHeroBlock({required this.isCompact});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final mascotSize = isCompact ? 72.0 : 92.0;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        24,
        MediaQuery.paddingOf(context).top + (isCompact ? 16 : 28),
        24,
        isCompact ? 24 : 36,
      ),
      decoration: const BoxDecoration(
        gradient: AppColorTokens.bloomOnboardingGradient,
      ),
      child: Column(
        children: [
          // 92x92 Mascot with bob and pulsing ring border
          BloomMascot(
            size: mascotSize,
            bob: true,
            pulseRing: true,
            borderRadius: isCompact ? 26 : 34,
          ),
          SizedBox(height: isCompact ? 16 : 24),
          // Headline: 27px/700, -0.03em, white
          Text(
            "I can read your bank\ntexts so you don't",
            style: AppTheme.bloomDisplay(
              isCompact ? 22 : 27,
              FontWeight.w700,
              letterSpacing: -0.03,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          // Sub: 14px #E2DCFF, max 272px
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 272),
            child: Text(
              'Everything stays on this phone. No account, no upload, no ads.',
              style: AppTheme.bloomDisplay(
                14,
                FontWeight.w400,
                color: const Color(0xFFE2DCFF),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomContentBlock extends ConsumerWidget {
  const _BottomContentBlock({
    required this.permission,
    required this.backfillStatus,
    required this.isCompact,
  });

  final AsyncValue<SmsPermissionStatus> permission;
  final SmsBackfillStatusState backfillStatus;
  final bool isCompact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = permission.valueOrNull ?? SmsPermissionStatus.denied;
    final isPermanentlyDenied = status == SmsPermissionStatus.permanentlyDenied;
    final isGranted = status == SmsPermissionStatus.granted;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 24,
        vertical: isCompact ? 16 : 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Three Benefit Rows (or Warning Row if denied/permanently denied)
          const _BenefitRow(
            icon: Icons.textsms_outlined,
            bgColor: Color(0xFFF6F4FE),
            tileColor: Color(0xFFE4DEFF),
            iconColor: Color(0xFF4F3FC4),
            title: 'Reads only money texts',
            subtitle: 'OTPs and personal messages are skipped entirely.',
          ),
          const SizedBox(height: 10),
          const _BenefitRow(
            icon: Icons.wifi_off_outlined,
            bgColor: Color(0xFFF1FBF6),
            tileColor: Color(0xFFD3F2E4),
            iconColor: Color(0xFF0E7A56),
            title: 'Works offline, forever',
            subtitle: 'Parsing and answers run on-device.',
          ),
          const SizedBox(height: 10),
          if (isPermanentlyDenied)
            const _WarningBenefitRow(
              title: 'Android is blocking us',
              subtitle: 'Open Settings > Apps > PaisaTrack > SMS to enable.',
            )
          else
            const _BenefitRow(
              icon: Icons.history_toggle_off_outlined,
              bgColor: Color(0xFFFFF7E4),
              tileColor: Color(0xFFF7E5BE),
              iconColor: Color(0xFF8A5A00),
              title: 'Ready in about 20 seconds',
              subtitle: "We'll read the last 6 months so today has context.",
            ),
          SizedBox(height: isCompact ? 16 : 24),

          // Progress Row / Live import count
          _ProgressRow(
            backfillStatus: backfillStatus,
            isGranted: isGranted,
          ),
          SizedBox(height: isCompact ? 16 : 24),

          // CTA Stack
          _CtaButtons(
            status: status,
            permission: permission,
          ),
        ],
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.icon,
    required this.bgColor,
    required this.tileColor,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color bgColor;
  final Color tileColor;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tileColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.bloomDisplay(
                    14,
                    FontWeight.w600,
                    color: AppColorTokens.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTheme.bloomDisplay(
                    12,
                    FontWeight.w400,
                    color: AppColorTokens.inkTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBenefitRow extends StatelessWidget {
  const _WarningBenefitRow({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColorTokens.bloomWarningBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColorTokens.bloomWarningBorder, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFF7E5BE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: AppColorTokens.bloomWarningText,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.bloomDisplay(
                    14,
                    FontWeight.w600,
                    color: AppColorTokens.bloomWarningText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTheme.bloomDisplay(
                    12,
                    FontWeight.w400,
                    color: AppColorTokens.bloomWarningText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.backfillStatus,
    required this.isGranted,
  });

  final SmsBackfillStatusState backfillStatus;
  final bool isGranted;

  @override
  Widget build(BuildContext context) {
    final isRunning = backfillStatus.stage == SmsBackfillStage.running;
    final processed = backfillStatus.processed;
    final total = backfillStatus.total;

    final String label;
    final double fillFraction;

    if (isRunning && processed > 0) {
      if (total != null && total > 0) {
        label = '$processed of ${formatIntWithCommas(total)} texts read';
        fillFraction = (processed / total).clamp(0.05, 1.0);
      } else {
        label = '$processed texts read';
        fillFraction = 0.5;
      }
    } else if (isGranted) {
      label = 'SMS access granted. Capture is on.';
      fillFraction = 1.0;
    } else {
      label = '1 of 3';
      fillFraction = 0.34;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F4FE),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: LinearProgressIndicator(
                  value: fillFraction,
                  backgroundColor: const Color(0xFFE4DEFF),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColorTokens.violetPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              label,
              style: AppTheme.bloomMono(
                12,
                FontWeight.w500,
                color: AppColorTokens.inkTertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String formatIntWithCommas(int value) {
    final text = value.toString();
    final buffer = StringBuffer();
    final len = text.length;
    for (var i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(text[i]);
    }
    return buffer.toString();
  }
}

class _CtaButtons extends ConsumerWidget {
  const _CtaButtons({
    required this.status,
    required this.permission,
  });

  final SmsPermissionStatus status;
  final AsyncValue<SmsPermissionStatus> permission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(smsPermissionControllerProvider.notifier);
    final isBusy = permission.isLoading;

    final String primaryLabel;
    final VoidCallback? onPrimaryTap;

    if (status == SmsPermissionStatus.permanentlyDenied) {
      primaryLabel = 'Open settings';
      onPrimaryTap = isBusy ? null : controller.openSettings;
    } else if (status == SmsPermissionStatus.granted) {
      primaryLabel = 'Continue to PaisaTrack';
      onPrimaryTap = () {
        ref.read(continueWithoutSmsProvider.notifier).state = true;
      };
    } else {
      primaryLabel = 'Allow SMS access';
      onPrimaryTap = isBusy ? null : controller.request;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 54px full-width pill #1B1830
        SizedBox(
          height: 54,
          child: FilledButton(
            onPressed: onPrimaryTap,
            style: FilledButton.styleFrom(
              backgroundColor: AppColorTokens.ink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(27),
              ),
              textStyle: AppTheme.bloomDisplay(15, FontWeight.w600),
            ),
            child: Text(primaryLabel),
          ),
        ),
        const SizedBox(height: 10),
        // Secondary plain text button #7A7596 13px
        Center(
          child: TextButton(
            onPressed: () {
              ref.read(continueWithoutSmsProvider.notifier).state = true;
            },
            child: Text(
              "I'll add things myself",
              style: AppTheme.bloomDisplay(
                13,
                FontWeight.w500,
                color: AppColorTokens.inkTertiary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

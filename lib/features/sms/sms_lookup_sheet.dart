import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../capture/permissions/sms_permission.dart';
import '../../capture/permissions/sms_permission_provider.dart';
import '../../capture/sms_backfill.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/bloom/bloom_sheet_scaffold.dart';
import '../dashboard/dashboard_providers.dart';

enum SmsLookupState {
  permissionNeeded,
  permanentlyDenied,
  ready,
  scanning,
  complete,
  partialFailure,
  error,
}

/// Dedicated SMS lookup sheet scanning the permitted inbox for financial messages.
class SmsLookupSheet extends ConsumerStatefulWidget {
  const SmsLookupSheet({super.key});

  @override
  ConsumerState<SmsLookupSheet> createState() => _SmsLookupSheetState();
}

class _SmsLookupSheetState extends ConsumerState<SmsLookupSheet> {
  SmsLookupState _state = SmsLookupState.ready;
  SmsImportProgress? _progress;
  SmsImportResult? _lastResult;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkPermissionState();
  }

  Future<void> _checkPermissionState() async {
    final status = await ref.read(smsPermissionGateProvider).status();
    if (!mounted) return;
    if (status == SmsPermissionStatus.permanentlyDenied) {
      setState(() => _state = SmsLookupState.permanentlyDenied);
    } else if (status != SmsPermissionStatus.granted) {
      setState(() => _state = SmsLookupState.permissionNeeded);
    } else {
      setState(() => _state = SmsLookupState.ready);
    }
  }

  Future<void> _requestPermission() async {
    await ref.read(smsPermissionControllerProvider.notifier).request();
    final status = ref.read(smsPermissionControllerProvider).valueOrNull ??
        SmsPermissionStatus.unknown;
    if (!mounted) return;
    if (status.isGranted) {
      setState(() => _state = SmsLookupState.ready);
      _startScan();
    } else if (status == SmsPermissionStatus.permanentlyDenied) {
      setState(() => _state = SmsLookupState.permanentlyDenied);
    } else {
      setState(() => _state = SmsLookupState.permissionNeeded);
    }
  }

  Future<void> _startScan({bool force = true}) async {
    setState(() {
      _state = SmsLookupState.scanning;
      _progress = const SmsImportProgress(processed: 0, failed: 0);
      _errorMessage = null;
    });

    try {
      final runner = await ref.read(smsHistoryImportRunnerProvider.future);
      final result = await runner.run(
        force: force,
        onProgress: (p) {
          if (mounted) {
            setState(() => _progress = p);
          }
        },
      );

      if (!mounted) return;
      setState(() {
        _lastResult = result;
        if (result.failed > 0) {
          _state = SmsLookupState.partialFailure;
        } else {
          _state = SmsLookupState.complete;
        }
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _state = SmsLookupState.error;
        _errorMessage = 'Could not scan SMS messages: ${err.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BloomSheetScaffold(
      showBack: false,
      showClose: true,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Row: Icon + Title + Reassurance
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color:
                          AppColorTokens.violetPrimary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.sms_rounded,
                      color: AppColorTokens.violetPrimary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Find transactions from SMS',
                          style: AppTheme.bloomDisplay(
                            18,
                            FontWeight.w700,
                            color: isDark
                                ? AppColorTokens.bloomDarkTextPrimary
                                : AppColorTokens.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Scanned on this phone. Personal messages stay private.',
                          style: AppTheme.bloomDisplay(
                            12,
                            FontWeight.w400,
                            color: isDark
                                ? AppColorTokens.bloomDarkTextTertiary
                                : AppColorTokens.inkTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // State Content
              _buildStateBody(isDark),

              const SizedBox(height: 24),

              // Action Buttons
              _buildActions(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStateBody(bool isDark) {
    switch (_state) {
      case SmsLookupState.permissionNeeded:
        return _buildCard(
          isDark: isDark,
          bgColor:
              isDark ? AppColorTokens.bloomDarkCard : const Color(0xFFF6F4FE),
          borderColor: isDark
              ? AppColorTokens.bloomDarkOutline
              : AppColorTokens.bloomHairline,
          icon: Icons.shield_outlined,
          iconColor: AppColorTokens.violetPrimary,
          title: 'SMS access is off',
          subtitle:
              'PaisaTrack reads transaction alerts and skips OTPs, promotions, and personal messages.',
        );

      case SmsLookupState.permanentlyDenied:
        return _buildCard(
          isDark: isDark,
          bgColor: isDark
              ? AppColorTokens.warningDark.withValues(alpha: 0.12)
              : const Color(0xFFFFF8E6),
          borderColor: isDark
              ? AppColorTokens.warningDark.withValues(alpha: 0.3)
              : const Color(0xFFFBE6B5),
          icon: Icons.settings_applications_rounded,
          iconColor: AppColorTokens.warningDark,
          title: 'SMS permission permanently denied',
          subtitle:
              'Open system settings to allow SMS access:\nSettings → Apps → PaisaTrack → Permissions → SMS',
        );

      case SmsLookupState.ready:
        return _buildCard(
          isDark: isDark,
          bgColor:
              isDark ? AppColorTokens.bloomDarkCard : const Color(0xFFF6F4FE),
          borderColor: isDark
              ? AppColorTokens.bloomDarkOutline
              : AppColorTokens.bloomHairline,
          icon: Icons.motion_photos_on_rounded,
          iconColor: AppColorTokens.emerald,
          title: 'Ready to scan inbox',
          subtitle:
              'Re-scanning preserves your edits, category confirmations, deletions, and manual entries.',
        );

      case SmsLookupState.scanning:
        final progress = _progress;
        final checked = _progress?.processed ?? 0;
        final total = _progress?.totalMessages;
        final found = _progress?.transactionsFound ?? 0;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:
                isDark ? AppColorTokens.bloomDarkCard : const Color(0xFFF6F4FE),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? AppColorTokens.bloomDarkOutline
                  : AppColorTokens.bloomHairline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColorTokens.violetPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Scanning SMS messages...',
                    style: AppTheme.bloomDisplay(
                      14,
                      FontWeight.w600,
                      color: isDark
                          ? AppColorTokens.bloomDarkTextPrimary
                          : AppColorTokens.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: (total != null && total > 0) ? (checked / total) : null,
                backgroundColor: isDark
                    ? AppColorTokens.bloomDarkTrack
                    : AppColorTokens.bloomChip,
                color: AppColorTokens.violetPrimary,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    total != null
                        ? '$checked of $total checked'
                        : '$checked messages checked',
                    style: AppTheme.bloomMono(
                      12,
                      FontWeight.w500,
                      color: isDark
                          ? AppColorTokens.bloomDarkTextSecondary
                          : AppColorTokens.inkSecondary,
                    ),
                  ),
                  Text(
                    '$found transactions found',
                    style: AppTheme.bloomMono(
                      12,
                      FontWeight.w600,
                      color: AppColorTokens.emerald,
                    ),
                  ),
                ],
              ),
              if (progress != null) ...[
                const SizedBox(height: 8),
                Text(
                  _scanOutcomeSummary(progress),
                  style: AppTheme.bloomMono(
                    11,
                    FontWeight.w400,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextTertiary
                        : AppColorTokens.inkTertiary,
                  ),
                ),
              ],
            ],
          ),
        );

      case SmsLookupState.complete:
        final res = _lastResult;
        final found = res?.transactionsFound ?? 0;

        return _buildCard(
          isDark: isDark,
          bgColor: isDark ? const Color(0xFF0F2D23) : const Color(0xFFE6F8F2),
          borderColor:
              isDark ? const Color(0xFF1E5B47) : const Color(0xFFA8ECE0),
          icon: Icons.check_circle_rounded,
          iconColor: AppColorTokens.emerald,
          title: found > 0 ? '$found transactions found' : "You're up to date",
          subtitle: res == null
              ? 'No scan result available.'
              : _scanOutcomeSummary(res),
        );

      case SmsLookupState.partialFailure:
        final res = _lastResult;
        final failed = res?.failed ?? 0;

        return _buildCard(
          isDark: isDark,
          bgColor: isDark ? const Color(0xFF2A2210) : const Color(0xFFFFF8E6),
          borderColor:
              isDark ? const Color(0xFF52421D) : const Color(0xFFFBE6B5),
          icon: Icons.warning_amber_rounded,
          iconColor: AppColorTokens.warningDark,
          title: 'Scan finished with some gaps',
          subtitle: res == null
              ? 'No scan result available.'
              : '${_scanOutcomeSummary(res)}\n$failed could not be read',
        );

      case SmsLookupState.error:
        return _buildCard(
          isDark: isDark,
          bgColor: isDark ? const Color(0xFF2E1617) : const Color(0xFFFDE8E8),
          borderColor:
              isDark ? const Color(0xFF5C2B2E) : const Color(0xFFF8B4B4),
          icon: Icons.error_outline_rounded,
          iconColor: AppColorTokens.errorDark,
          title: 'Scan failed',
          subtitle:
              _errorMessage ?? 'An error occurred while reading messages.',
        );
    }
  }

  String _scanOutcomeSummary(SmsImportProgress result) {
    return '${result.scanned} scanned · ${result.filterRejected} rejected · '
        '${result.unknownSender} unknown sender · ${result.accepted} accepted\n'
        '${result.parsed} parsed · ${result.unparsed} unparsed · '
        '${result.transactionsFound} created · ${result.alreadyKnown} already known';
  }

  Widget _buildCard({
    required bool isDark,
    required Color bgColor,
    required Color borderColor,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.bloomDisplay(
                    14,
                    FontWeight.w700,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextPrimary
                        : AppColorTokens.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTheme.bloomDisplay(
                    12,
                    FontWeight.w400,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextSecondary
                        : AppColorTokens.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(bool isDark) {
    switch (_state) {
      case SmsLookupState.permissionNeeded:
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColorTokens.violetPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _requestPermission,
                child: const Text('Allow SMS access'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Not now'),
            ),
          ],
        );

      case SmsLookupState.permanentlyDenied:
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColorTokens.violetPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () async {
                  await ref
                      .read(smsPermissionControllerProvider.notifier)
                      .openSettings();
                },
                child: const Text('Open Android settings'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );

      case SmsLookupState.ready:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColorTokens.violetPrimary,
                ),
                onPressed: () => _startScan(force: true),
                child: const Text('Scan now'),
              ),
            ),
          ],
        );

      case SmsLookupState.scanning:
        return const SizedBox.shrink();

      case SmsLookupState.complete:
        return SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColorTokens.violetPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(homeTabControllerProvider.notifier).state = 1;
            },
            child: const Text('View Activity'),
          ),
        );

      case SmsLookupState.partialFailure:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  ref.read(homeTabControllerProvider.notifier).state = 1;
                },
                child: const Text('View Activity'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColorTokens.warningDark,
                ),
                onPressed: () => _startScan(force: true),
                child: const Text('Retry failed messages'),
              ),
            ),
          ],
        );

      case SmsLookupState.error:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColorTokens.violetPrimary,
                ),
                onPressed: () => _startScan(force: true),
                child: const Text('Try again'),
              ),
            ),
          ],
        );
    }
  }
}

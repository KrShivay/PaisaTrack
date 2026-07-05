import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../capture/permissions/sms_permission.dart';
import '../../capture/permissions/sms_permission_provider.dart';

/// First-run screen that explains why PaisaTrack needs SMS access and requests
/// the permission.
///
/// Denial is non-fatal: the app stays usable and the screen explains the
/// degraded state (no automatic capture) rather than blocking the user.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permission = ref.watch(smsPermissionControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('PaisaTrack')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Read bank SMS on this device',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'PaisaTrack turns your bank and UPI messages into transactions. '
                  'Messages are parsed on your device and never leave it. '
                  'Grant SMS access to capture them automatically.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                _PermissionBody(permission: permission),
              ],
            ),
          ),
        ),
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
            const SizedBox(height: 16),
            _GrantButton(onPressed: isBusy ? null : controller.request),
          ],
        ),
      AsyncError() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _DegradedNotice(
              message: 'Could not read the SMS permission state. Try again.',
            ),
            const SizedBox(height: 16),
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
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.check_circle_outline),
        SizedBox(width: 8),
        Flexible(child: Text('SMS access granted. Capture is on.')),
      ],
    );
  }
}

class _DegradedNotice extends StatelessWidget {
  const _DegradedNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      textAlign: TextAlign.center,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}

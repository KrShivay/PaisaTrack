import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../capture/permissions/sms_permission.dart';
import '../../capture/permissions/sms_permission_provider.dart';

/// Shows the current SMS permission and the recovery action for that state.
///
/// The card is intentionally shared by Settings and Activity so the two
/// surfaces cannot drift in their wording or recovery behavior.
class SmsPermissionStatusCard extends ConsumerWidget {
  const SmsPermissionStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permission = ref.watch(smsPermissionControllerProvider);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: permission.when(
          loading: () => const _PermissionContent(
            icon: Icons.sync,
            title: 'Checking SMS access',
            subtitle: 'Checking whether transaction messages are available.',
          ),
          error: (_, __) => _PermissionContent(
            icon: Icons.warning_amber_rounded,
            title: 'SMS access status unavailable',
            subtitle: 'Check again before scanning transaction messages.',
            action: OutlinedButton(
              onPressed: () => ref
                  .read(smsPermissionControllerProvider.notifier)
                  .recheckStatus(),
              child: const Text('Check again'),
            ),
          ),
          data: (status) => _contentForStatus(ref, status),
        ),
      ),
    );
  }

  Widget _contentForStatus(WidgetRef ref, SmsPermissionStatus status) {
    final controller = ref.read(smsPermissionControllerProvider.notifier);
    return switch (status) {
      SmsPermissionStatus.granted => const _PermissionContent(
          icon: Icons.check_circle_outline,
          title: 'SMS access is on',
          subtitle:
              'PaisaTrack can scan transaction messages when you choose to import them.',
        ),
      SmsPermissionStatus.denied => _PermissionContent(
          icon: Icons.sms_outlined,
          title: 'SMS access is off',
          subtitle: 'Allow access to scan transaction messages on this phone.',
          action: FilledButton.tonal(
            onPressed: controller.request,
            child: const Text('Allow SMS access'),
          ),
        ),
      SmsPermissionStatus.permanentlyDenied => _PermissionContent(
          icon: Icons.settings_outlined,
          title: 'SMS access is blocked',
          subtitle: 'Enable SMS access in Android settings to scan messages.',
          action: FilledButton.tonal(
            onPressed: controller.openSettings,
            child: const Text('Open app settings'),
          ),
        ),
      SmsPermissionStatus.unknown => _PermissionContent(
          icon: Icons.help_outline,
          title: 'SMS access status unknown',
          subtitle: 'Check again before scanning transaction messages.',
          action: OutlinedButton(
            onPressed: controller.recheckStatus,
            child: const Text('Check again'),
          ),
        ),
    };
  }
}

class _PermissionContent extends StatelessWidget {
  const _PermissionContent({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(subtitle),
              if (action != null) ...[
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: action!),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../settings/app_data_reset_service.dart';

class KeyLossScreen extends ConsumerStatefulWidget {
  const KeyLossScreen({super.key});

  @override
  ConsumerState<KeyLossScreen> createState() => _KeyLossScreenState();
}

class _KeyLossScreenState extends ConsumerState<KeyLossScreen> {
  bool _busy = false;

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset local database?'),
        content: const Text(
          'Your existing local database is unreadable and will be permanently deleted. '
          'You can set up a fresh database or restore from a previously exported backup file.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset Data'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(appDataResetServiceProvider).deleteEverything();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Database Recovery'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.lock_reset,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Encryption Key Unavailable',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'The Android Keystore encryption key needed to unlock your local database '
                'is no longer accessible. To prevent data corruption, database access has been locked.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              if (_busy)
                const Center(child: CircularProgressIndicator())
              else ...[
                FilledButton.icon(
                  key: const ValueKey('key_loss_reset_button'),
                  onPressed: _confirmReset,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Reset & Create Fresh Database'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

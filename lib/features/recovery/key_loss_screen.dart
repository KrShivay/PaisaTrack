import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../capture/permissions/sms_permission_provider.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/crypto/database_cipher.dart';
import '../../data/db/database_provider.dart';
import '../backup/encrypted_backup_service.dart';
import 'database_recovery_service.dart';

class KeyLossScreen extends ConsumerStatefulWidget {
  const KeyLossScreen({super.key});

  @override
  ConsumerState<KeyLossScreen> createState() => _KeyLossScreenState();
}

class _KeyLossScreenState extends ConsumerState<KeyLossScreen> {
  final _passphraseController = TextEditingController();
  bool _busy = false;
  String? _message;
  String? _error;
  EncryptedBackupProgress? _progress;

  @override
  void dispose() {
    _passphraseController.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    if (_passphraseController.text.trim().isEmpty) {
      setState(() => _error = 'Enter the backup passphrase to continue.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _message = null;
      _progress = null;
    });
    try {
      final recovery = await ref.read(databaseRecoveryServiceProvider.future);
      final result = await recovery.restoreFromDocument(
        passphrase: _passphraseController.text,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (result == null) {
        if (mounted) {
          setState(() => _message = 'Backup selection was cancelled.');
        }
        return;
      }

      ref.read(continueWithoutSmsProvider.notifier).state = true;
      ref.invalidate(appDatabaseProvider);
      await ref.read(appDatabaseProvider.future);
      if (mounted) {
        final retainedCopy = result.preservedFiles == 0
            ? 'No earlier database files were present to archive.'
            : 'A verified copy of the previous encrypted database remains in app storage.';
        setState(
          () => _message =
              'Recovered ${result.transactionCount} transactions and '
                  '${result.paymentSourceCount} payment sources. $retainedCopy',
        );
      }
    } on EncryptedBackupException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on DatabaseKeyLostError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'The backup could not be restored. Any previous encrypted '
                  'database and its legacy key were left unchanged. Check the '
                  'passphrase and try again.',
        );
      }
    } finally {
      if (mounted) {
        _passphraseController.clear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Database Recovery'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Icon(
                  Icons.lock_reset,
                  size: 56,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Encryption Key Unavailable',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'The Android Keystore key for the current database cannot '
                  'be read. Restore an encrypted .ptrack backup to create a '
                  'new database. The existing encrypted database and its key '
                  'are kept unchanged.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                TextField(
                  key: const ValueKey('recovery_passphrase_field'),
                  controller: _passphraseController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _busy ? null : _restore(),
                  decoration: const InputDecoration(
                    labelText: 'Backup passphrase',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  key: const ValueKey('key_loss_restore_button'),
                  onPressed: _busy ? null : _restore,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.restore),
                  label: Text(_busy ? 'Restoring backup…' : 'Restore backup'),
                ),
                if (_progress case final progress?) ...[
                  const SizedBox(height: AppSpacing.md),
                  LinearProgressIndicator(
                    value:
                        progress.totalBytes == null || progress.totalBytes == 0
                            ? null
                            : progress.processedBytes / progress.totalBytes!,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _phaseLabel(progress.phase),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_error case final error?) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    error,
                    key: const ValueKey('recovery_error_message'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_message case final message?) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    message,
                    key: const ValueKey('recovery_status_message'),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _phaseLabel(EncryptedBackupProgressPhase phase) => switch (phase) {
        EncryptedBackupProgressPhase.preparing => 'Preparing restore…',
        EncryptedBackupProgressPhase.encrypting => 'Encrypting backup…',
        EncryptedBackupProgressPhase.decrypting => 'Checking backup…',
        EncryptedBackupProgressPhase.restoring => 'Restoring records…',
        EncryptedBackupProgressPhase.completed => 'Checking restored database…',
      };
}

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../capture/permissions/sms_permission.dart';
import '../../capture/permissions/sms_permission_provider.dart';
import '../../capture/sms_backfill.dart';
import '../../core/constants.dart';
import '../../core/platform/system_document_gateway.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/paisa_colors.dart';
import '../../core/widgets/app_state_views.dart';
import '../../intelligence/llm/llm_runtime.dart';
import '../backup/encrypted_backup_service.dart';
import '../dev/model_metrics_screen.dart';
import '../dev/unparsed_sms_screen.dart';
import 'app_data_reset_service.dart';
import 'app_settings.dart';
import 'category_manager_screen.dart';
import 'payee_labels_screen.dart';
import 'payment_sources_screen.dart';

const minimumBackupPassphraseLength = 12;

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settings.when(
        data: (value) => ListView(
          padding: AppSpacing.screen,
          children: [
            _Section(
              title: 'Appearance',
              children: [
                SegmentedButton<AppThemeChoice>(
                  segments: [
                    for (final choice in AppThemeChoice.values)
                      ButtonSegment(
                        value: choice,
                        icon: Icon(_themeIcon(choice)),
                        label: Text(choice.label),
                      ),
                  ],
                  selected: {value.themeChoice},
                  onSelectionChanged: (selection) {
                    ref
                        .read(appSettingsControllerProvider.notifier)
                        .setThemeChoice(selection.single);
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const _Section(
              title: 'Intelligence',
              children: [_LlmModelTile()],
            ),
            _Section(
              title: 'Ask PaisaTrack',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.question_answer_outlined),
                  title: const Text('Ask PaisaTrack daily limit'),
                  subtitle: Text('${value.askDailyBudget} questions per day'),
                ),
                Slider(
                  value: value.askDailyBudget.toDouble(),
                  min: 0,
                  max: 5,
                  divisions: 5,
                  label: value.askDailyBudget.toString(),
                  onChanged: (next) {
                    ref
                        .read(appSettingsControllerProvider.notifier)
                        .setAskDailyBudget(next.round());
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _Section(
              title: 'Categories and learning',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Categories'),
                  subtitle: const Text(
                    'Names, icons, merchant learning and matching rules',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => const CategoryManagerScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _Section(
              title: 'Accounts and transactions',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_balance_outlined),
                  title: const Text('Accounts and payment sources'),
                  subtitle: const Text(
                    'Nicknames, analytics inclusion and owned transfers',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PaymentSourcesScreen(),
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Payee labels'),
                  subtitle: const Text(
                    'Name merchants, UPI IDs and counterparties',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PayeeLabelsScreen(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const _Section(
              title: 'Notifications',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.notifications_outlined),
                  title: Text('Review reminders'),
                  subtitle: Text(
                    'Shown only when transactions need your attention',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const _Section(
              title: 'Privacy and security',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.lock_outline),
                  title: Text('Local processing'),
                  subtitle: Text(
                    'Financial messages, learning and questions stay on device',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _Section(
              title: 'Data',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.upload_file_outlined),
                  title: const Text('Export encrypted backup'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _exportBackup(context, ref),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Import encrypted backup'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _importBackup(context, ref),
                ),
                const _SmsHistoryImportTile(),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _Section(
              title: 'Delete app data',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: PaisaColors.of(context).debit,
                  ),
                  title: const Text('Delete everything'),
                  subtitle: const Text(
                    'Permanently removes transactions, settings and learning',
                  ),
                  onTap: () => _confirmDeleteEverything(context, ref),
                ),
              ],
            ),
            if (kDebugMode) ...[
              const SizedBox(height: AppSpacing.xl),
              const _DeveloperOptionsSection(),
            ],
          ],
        ),
        error: (error, stackTrace) {
          developer.log(
            'Failed to load settings',
            name: 'paisatrack.settings',
            error: error,
            stackTrace: stackTrace,
          );
          return ErrorStateView(
            message: 'Could not load settings.',
            onRetry: () => ref.invalidate(appSettingsControllerProvider),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  IconData _themeIcon(AppThemeChoice choice) {
    return switch (choice) {
      AppThemeChoice.dark => Icons.dark_mode,
      AppThemeChoice.light => Icons.light_mode,
      AppThemeChoice.system => Icons.brightness_auto,
    };
  }

  Future<void> _confirmDeleteEverything(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete everything?'),
        content: const Text(
          'This wipes transactions, SMS records, categories, rules, feedback, '
          'settings, and the database encryption key.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final result =
          await ref.read(appDataResetServiceProvider).deleteEverything();
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Deleted app data and recreated ${result.categoryCount} categories.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Delete failed: $error')),
      );
    }
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    final passphrase = await _askPassphrase(
      context,
      title: 'Export encrypted backup',
      action: 'Export',
      minimumLength: minimumBackupPassphraseLength,
      confirmPassphrase: true,
    );
    if (passphrase == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = await ref.read(encryptedBackupServiceProvider.future);
      final bytes = await service.exportBytes(passphrase: passphrase);
      final saved = await ref.read(systemDocumentGatewayProvider).saveDocument(
            suggestedName: encryptedBackupFileName,
            mimeType: 'application/octet-stream',
            bytes: bytes,
          );
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            saved ? 'Encrypted backup saved' : 'Export cancelled',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Export failed: $error')),
      );
    }
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final bytes = await ref.read(systemDocumentGatewayProvider).openDocument(
          mimeType: 'application/octet-stream',
        );
    if (!context.mounted) return;
    if (bytes == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Import cancelled')),
      );
      return;
    }

    final passphrase = await _askPassphrase(
      context,
      title: 'Import encrypted backup',
      action: 'Import',
      minimumLength: minimumBackupPassphraseLength,
    );
    if (passphrase == null || !context.mounted) return;

    try {
      final service = await ref.read(encryptedBackupServiceProvider.future);
      await service.importBytes(bytes: bytes, passphrase: passphrase);
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Encrypted backup imported')),
      );
    } catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Import failed: $error')),
      );
    }
  }

  Future<String?> _askPassphrase(
    BuildContext context, {
    required String title,
    required String action,
    int? minimumLength,
    bool confirmPassphrase = false,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _PassphraseDialog(
        title: title,
        action: action,
        minimumLength: minimumLength,
        confirmPassphrase: confirmPassphrase,
      ),
    );
  }
}

class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog({
    required this.title,
    required this.action,
    required this.minimumLength,
    required this.confirmPassphrase,
  });

  final String title;
  final String action;
  final int? minimumLength;
  final bool confirmPassphrase;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  final _confirmationController = TextEditingController();

  @override
  void dispose() {
    _controller.clear();
    _confirmationController.clear();
    _controller.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _controller,
              autofocus: true,
              obscureText: true,
              textInputAction: widget.confirmPassphrase
                  ? TextInputAction.next
                  : TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Passphrase'),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Enter a passphrase';
                }
                if (widget.minimumLength != null &&
                    value.length < widget.minimumLength!) {
                  return 'Use at least ${widget.minimumLength} characters';
                }
                return null;
              },
              onFieldSubmitted:
                  widget.confirmPassphrase ? null : (_) => _submit(),
            ),
            if (widget.confirmPassphrase) ...[
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _confirmationController,
                obscureText: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Confirm passphrase',
                ),
                validator: (value) => value == _controller.text
                    ? null
                    : 'Passphrases do not match',
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}

class _SmsHistoryImportTile extends ConsumerStatefulWidget {
  const _SmsHistoryImportTile();

  @override
  ConsumerState<_SmsHistoryImportTile> createState() =>
      _SmsHistoryImportTileState();
}

class _SmsHistoryImportTileState extends ConsumerState<_SmsHistoryImportTile> {
  SmsImportProgress? _progress;
  bool _busy = false;

  Future<void> _importHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Re-import all SMS history?'),
        content: const Text(
          'PaisaTrack will scan all financial SMS in your inbox. This can '
          'take time for a large inbox. Existing edits, confirmations, '
          'deletions, and manual transactions will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Re-import'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    var permission = ref.read(smsPermissionControllerProvider).valueOrNull ??
        SmsPermissionStatus.unknown;
    if (!permission.isGranted) {
      await ref.read(smsPermissionControllerProvider.notifier).request();
      permission = ref.read(smsPermissionControllerProvider).valueOrNull ??
          SmsPermissionStatus.unknown;
    }
    if (!mounted) return;
    if (!permission.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SMS permission is required to import history.'),
        ),
      );
      return;
    }

    setState(() {
      _busy = true;
      _progress = const SmsImportProgress(processed: 0, failed: 0);
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final runner = await ref.read(smsHistoryImportRunnerProvider.future);
      final result = await runner.run(
        force: true,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.failed == 0
                ? 'SMS history import complete: '
                    '${result.processed} messages processed.'
                : 'SMS history import finished: ${result.processed} processed, '
                    '${result.failed} failed. You can re-import to retry.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('SMS history import failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.sms_outlined),
      title: const Text('Re-import all SMS history'),
      subtitle: Text(
        _busy && progress != null
            ? '${progress.processed} processed'
                '${progress.failed == 0 ? '' : ' · ${progress.failed} failed'}'
            : 'Scan the full inbox again without overwriting your edits',
      ),
      trailing: _busy
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: _busy ? null : _importHistory,
    );
  }
}

class _DeveloperOptionsSection extends StatelessWidget {
  const _DeveloperOptionsSection();

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: Text(
        'Developer options',
        style: Theme.of(context).textTheme.labelMedium,
      ),
      children: [
        const _FlagTile(
          title: 'Local LLM parsing',
          enabled: AppConstants.enableLocalLlm,
        ),
        const _FlagTile(
          title: 'Narrative insights',
          enabled: AppConstants.enableNarrativeInsights,
        ),
        if (kDebugMode) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Unparsed SMS diagnostics'),
            subtitle: const Text('Template misses and parser guardrails'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const UnparsedSmsScreen(),
              ),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.query_stats_outlined),
            title: const Text('Model metrics'),
            subtitle: const Text('Classifier and review feedback diagnostics'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ModelMetricsScreen(),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _LlmModelTile extends ConsumerStatefulWidget {
  const _LlmModelTile();

  @override
  ConsumerState<_LlmModelTile> createState() => _LlmModelTileState();
}

class _LlmModelTileState extends ConsumerState<_LlmModelTile> {
  bool? _available;
  bool? _supported;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final runtime = ref.read(llmRuntimeProvider);
    final results = await Future.wait([
      runtime.isModelAvailable(),
      runtime.isDeviceSupported(),
    ]);
    if (!mounted) return;
    setState(() {
      _available = results[0];
      _supported = results[1];
    });
  }

  Future<void> _download() async {
    setState(() => _busy = true);
    final succeeded =
        await ref.read(llmRuntimeProvider).downloadModelWithRetry();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _available = succeeded;
    });
    if (!succeeded) {
      _showDownloadFailureDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI model downloaded')),
      );
    }
  }

  void _showDownloadFailureDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Model download failed'),
        content: const Text(
          'The AI model download was interrupted or failed. Check your internet connection and try again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _download();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    final succeeded = await ref.read(llmRuntimeProvider).deleteModel();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _available = !succeeded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = switch ((_supported, _available)) {
      (false, _) => 'Unsupported on this device (requires at least 3 GB RAM)',
      (_, true) => 'Downloaded · app-private storage',
      (true, false) => 'Not downloaded',
      _ => 'Checking device…',
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Qwen2.5 0.5B · 547 MB'),
      subtitle: Text('$status\nPrompts and inference stay on this device.'),
      isThreeLine: true,
      trailing: _busy
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : _available == true
              ? IconButton(
                  tooltip: 'Delete AI model',
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                )
              : FilledButton(
                  onPressed: _supported == true ? _download : null,
                  child: const Text('Download'),
                ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        ...children,
      ],
    );
  }
}

class _FlagTile extends StatelessWidget {
  const _FlagTile({
    required this.title,
    required this.enabled,
  });

  final String title;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: const Text('Read-only until its phase lands'),
      value: enabled,
      onChanged: null,
    );
  }
}

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/platform/system_document_gateway.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/paisa_colors.dart';
import '../../intelligence/llm/llm_runtime.dart';
import '../backup/encrypted_backup_service.dart';
import '../dev/model_metrics_screen.dart';
import '../dev/unparsed_sms_screen.dart';
import 'app_data_reset_service.dart';
import 'app_settings.dart';
import 'category_manager_screen.dart';

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
            const SizedBox(height: AppSpacing.xl),
            _Section(
              title: 'Ask budget',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${value.askDailyBudget} asks per day'),
                  subtitle: const Text('Default budget is 2 asks per day'),
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
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => const CategoryManagerScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.category),
                  label: const Text('Manage categories'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _Section(
              title: 'Data',
              children: [
                OutlinedButton.icon(
                  onPressed: () => _exportBackup(context, ref),
                  icon: const Icon(Icons.lock),
                  label: const Text('Export encrypted backup'),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: () => _importBackup(context, ref),
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Import encrypted backup'),
                ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: () => _confirmDeleteEverything(context, ref),
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Delete everything'),
                  style: FilledButton.styleFrom(
                    backgroundColor: PaisaColors.of(context).debit,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const _DeveloperOptionsSection(),
          ],
        ),
        error: (error, stackTrace) => Center(
          child: Text('Settings unavailable: $error'),
        ),
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
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Passphrase'),
          onSubmitted: (_) {
            Navigator.of(context).pop(controller.text);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(action),
          ),
        ],
      ),
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
    final succeeded = await ref.read(llmRuntimeProvider).downloadModel();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _available = succeeded;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          succeeded ? 'AI model downloaded' : 'Model download paused or failed',
        ),
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
      (false, _) => 'Unsupported on this device (requires about 2.2 GB RAM)',
      (_, true) => 'Downloaded · app-private storage',
      (true, false) => 'Not downloaded',
      _ => 'Checking device…',
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Qwen2.5 1.5B · 1.6 GB'),
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

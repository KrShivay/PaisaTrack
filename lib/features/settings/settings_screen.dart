import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../capture/permissions/sms_permission.dart';
import '../../capture/permissions/sms_permission_provider.dart';
import '../../capture/sms_backfill.dart';
import '../../core/platform/system_document_gateway.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../backup/encrypted_backup_service.dart';
import '../dev/model_metrics_screen.dart';
import '../dev/unparsed_sms_screen.dart';
import 'app_data_reset_service.dart';
import 'app_settings.dart';
import 'category_manager_screen.dart';
import 'payee_labels_screen.dart';
import 'payment_sources_screen.dart';

const minimumBackupPassphraseLength =
    EncryptedBackupService.minimumPassphraseLength;

/// Redesigned Bloom Settings screen with banner, theme toggle, backup, categories, and data reset.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settingsAsync = ref.watch(appSettingsControllerProvider);

    return Scaffold(
      backgroundColor:
          isDark ? AppColorTokens.bloomDarkBase : AppColorTokens.bloomBase,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Settings',
          style: AppTheme.bloomDisplay(
            20,
            FontWeight.w700,
            letterSpacing: -0.03,
            color: isDark
                ? AppColorTokens.bloomDarkTextPrimary
                : AppColorTokens.ink,
          ),
        ),
      ),
      body: settingsAsync.when(
        data: (settings) => ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            // App Banner Card
            _AppBannerCard(isDark: isDark),
            const SizedBox(height: 24),

            // Appearance Section
            _SettingsSection(
              title: 'APPEARANCE',
              isDark: isDark,
              child: Column(
                children: [
                  Row(
                    children: [
                      for (final choice in AppThemeChoice.values) ...[
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              ref
                                  .read(appSettingsControllerProvider.notifier)
                                  .setThemeChoice(choice);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: settings.themeChoice == choice
                                    ? (isDark
                                        ? AppColorTokens.violetPrimary
                                        : AppColorTokens.ink)
                                    : (isDark
                                        ? AppColorTokens.bloomDarkBase
                                        : Colors.white),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                choice.label,
                                style: AppTheme.bloomDisplay(
                                  13,
                                  FontWeight.w600,
                                  color: settings.themeChoice == choice
                                      ? Colors.white
                                      : (isDark
                                          ? AppColorTokens
                                              .bloomDarkTextSecondary
                                          : AppColorTokens.inkSecondary),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                        if (choice != AppThemeChoice.values.last)
                          const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Categories & Learning Section
            _SettingsSection(
              title: 'CATEGORIES & LEARNING',
              isDark: isDark,
              child: Column(
                children: [
                  _TileRow(
                    icon: Icons.category_outlined,
                    title: 'Categories',
                    subtitle: 'Names, icons, and category matching rules',
                    isDark: isDark,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CategoryManagerScreen(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  _TileRow(
                    icon: Icons.label_outline,
                    title: 'Payee & merchant labels',
                    subtitle: 'Clean display names for merchants',
                    isDark: isDark,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PayeeLabelsScreen(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  _TileRow(
                    icon: Icons.account_balance_outlined,
                    title: 'Payment sources',
                    subtitle: 'Bank accounts, credit cards, and wallets',
                    isDark: isDark,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PaymentSourcesScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Data & Backup Section
            _SettingsSection(
              title: 'DATA & BACKUP',
              isDark: isDark,
              child: Column(
                children: [
                  _TileRow(
                    icon: Icons.upload_file_outlined,
                    title: 'Export backup',
                    subtitle: 'Create encrypted backup of your transactions',
                    isDark: isDark,
                    onTap: () => _exportBackup(context, ref),
                  ),
                  const Divider(height: 1),
                  _TileRow(
                    icon: Icons.download_outlined,
                    title: 'Import backup',
                    subtitle: 'Restore transactions from backup file',
                    isDark: isDark,
                    onTap: () => _importBackup(context, ref),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: _SmsImportTile(isDark: isDark),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Privacy & Local AI Section
            _SettingsSection(
              title: 'PRIVACY & LOCAL AI',
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LlmModelTile(isDark: isDark),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Text(
                    'ASK PAISATRACK DAILY BUDGET',
                    style: AppTheme.bloomDisplay(
                      10,
                      FontWeight.w600,
                      letterSpacing: 0.1,
                      color: isDark
                          ? AppColorTokens.bloomDarkTextTertiary
                          : AppColorTokens.inkTertiary,
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: settings.askDailyBudget.toDouble(),
                          min: 0,
                          max: 5,
                          divisions: 5,
                          activeColor: AppColorTokens.violetPrimary,
                          onChanged: (next) {
                            ref
                                .read(appSettingsControllerProvider.notifier)
                                .setAskDailyBudget(next.round());
                          },
                        ),
                      ),
                      Text(
                        '${settings.askDailyBudget}/day',
                        style: AppTheme.bloomMono(
                          12,
                          FontWeight.w600,
                          color: isDark
                              ? AppColorTokens.bloomDarkTextPrimary
                              : AppColorTokens.ink,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (kDebugMode) ...[
              const _DeveloperOptionsSection(),
              const SizedBox(height: 20),
            ],

            // Destructive Reset Section
            _ResetDataButton(isDark: isDark),

            const SizedBox(height: 40),
          ],
        ),
        loading: () =>
            const Center(child: BloomSkeleton(width: 280, height: 200)),
        error: (err, _) => Center(child: Text('Error: $err')),
      ),
    );
  }

  static Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    final passphrase = await _promptPassphrase(
      context: context,
      title: 'Export Encrypted Backup',
      confirmLabel: 'Export',
    );
    if (passphrase == null || !context.mounted) return;

    try {
      final service = await ref.read(encryptedBackupServiceProvider.future);
      final bytes = await service.exportBytes(passphrase: passphrase);
      final gateway = ref.read(systemDocumentGatewayProvider);
      final success = await gateway.saveDocument(
        suggestedName: 'PaisaTrack_backup.json',
        mimeType: 'application/json',
        bytes: bytes,
      );
      if (context.mounted && success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup exported successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  static Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    try {
      final gateway = ref.read(systemDocumentGatewayProvider);
      final bytes = await gateway.openDocument(mimeType: 'application/json');
      if (bytes == null || !context.mounted) return;

      final passphrase = await _promptPassphrase(
        context: context,
        title: 'Import Encrypted Backup',
        confirmLabel: 'Import',
      );
      if (passphrase == null || !context.mounted) return;

      final service = await ref.read(encryptedBackupServiceProvider.future);
      await service.importBytes(bytes: bytes, passphrase: passphrase);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup imported successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    }
  }

  static Future<String?> _promptPassphrase({
    required BuildContext context,
    required String title,
    required String confirmLabel,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: 'Enter passphrase (min 12 chars)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }
}

class _AppBannerCard extends StatelessWidget {
  const _AppBannerCard({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? AppColorTokens.violetPrimary.withValues(alpha: 0.16)
            : const Color(0xFFF3EFFF),
        borderRadius: BorderRadius.circular(AppRadius.bloomCard),
        border: Border.all(
          color: isDark
              ? AppColorTokens.violetPrimary.withValues(alpha: 0.3)
              : const Color(0xFFDED6FD),
        ),
      ),
      child: Row(
        children: [
          const BloomMascot(
            size: 40,
            bob: true,
            pulseRing: true,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PaisaTrack Bloom',
                  style: AppTheme.bloomDisplay(
                    16,
                    FontWeight.w700,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextPrimary
                        : AppColorTokens.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Version 2.4.0 · 100% On-Device & Private',
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
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.child,
    required this.isDark,
  });

  final String title;
  final Widget child;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.bloomCard),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTheme.bloomDisplay(
                10,
                FontWeight.w600,
                letterSpacing: 0.1,
                color: isDark
                    ? AppColorTokens.bloomDarkTextTertiary
                    : AppColorTokens.inkTertiary,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _TileRow extends StatelessWidget {
  const _TileRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        icon,
        color: isDark
            ? AppColorTokens.bloomDarkTextSecondary
            : AppColorTokens.inkSecondary,
      ),
      title: Text(
        title,
        style: AppTheme.bloomDisplay(
          14,
          FontWeight.w600,
          color:
              isDark ? AppColorTokens.bloomDarkTextPrimary : AppColorTokens.ink,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: AppTheme.bloomDisplay(
          12,
          FontWeight.w400,
          color: isDark
              ? AppColorTokens.bloomDarkTextTertiary
              : AppColorTokens.inkTertiary,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: isDark
            ? AppColorTokens.bloomDarkTextTertiary
            : AppColorTokens.inkTertiary,
      ),
      onTap: onTap,
    );
  }
}

class _LlmModelTile extends StatelessWidget {
  const _LlmModelTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.psychology_outlined,
        color: isDark
            ? AppColorTokens.bloomDarkTextSecondary
            : AppColorTokens.inkSecondary,
      ),
      title: Text(
        'On-device AI engine',
        style: AppTheme.bloomDisplay(
          14,
          FontWeight.w600,
          color:
              isDark ? AppColorTokens.bloomDarkTextPrimary : AppColorTokens.ink,
        ),
      ),
      subtitle: Text(
        'Engine active · 100% On-device',
        style: AppTheme.bloomDisplay(
          12,
          FontWeight.w400,
          color: isDark
              ? AppColorTokens.bloomDarkTextTertiary
              : AppColorTokens.inkTertiary,
        ),
      ),
    );
  }
}

class _SmsImportTile extends ConsumerStatefulWidget {
  const _SmsImportTile({required this.isDark});

  final bool isDark;

  @override
  ConsumerState<_SmsImportTile> createState() => _SmsImportTileState();
}

class _SmsImportTileState extends ConsumerState<_SmsImportTile> {
  bool _busy = false;
  SmsImportProgress? _progress;

  Future<void> _importHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Re-import SMS history?'),
        content: const Text(
          'This rescans your SMS inbox for transactions. Existing edits will be preserved.',
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
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.failed == 0
                ? 'SMS import complete: ${result.processed} processed.'
                : 'SMS import finished: ${result.processed} processed, ${result.failed} failed.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('SMS import failed: $e')),
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
      leading: Icon(
        Icons.sms_outlined,
        color: widget.isDark
            ? AppColorTokens.bloomDarkTextSecondary
            : AppColorTokens.inkSecondary,
      ),
      title: Text(
        'Re-import all SMS history',
        style: AppTheme.bloomDisplay(
          14,
          FontWeight.w600,
          color: widget.isDark
              ? AppColorTokens.bloomDarkTextPrimary
              : AppColorTokens.ink,
        ),
      ),
      subtitle: Text(
        _busy && progress != null
            ? '${progress.processed} processed'
                '${progress.failed == 0 ? '' : ' · ${progress.failed} failed'}'
            : 'Rescan inbox without overwriting user edits',
        style: AppTheme.bloomDisplay(
          12,
          FontWeight.w400,
          color: widget.isDark
              ? AppColorTokens.bloomDarkTextTertiary
              : AppColorTokens.inkTertiary,
        ),
      ),
      trailing: _busy
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              Icons.chevron_right,
              color: widget.isDark
                  ? AppColorTokens.bloomDarkTextTertiary
                  : AppColorTokens.inkTertiary,
            ),
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
        style: AppTheme.bloomDisplay(13, FontWeight.w600),
      ),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.analytics_outlined),
          title: const Text('Model metrics'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ModelMetricsScreen(),
            ),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.sms_failed_outlined),
          title: const Text('Unparsed SMS list'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const UnparsedSmsScreen(),
            ),
          ),
        ),
      ],
    );
  }
}

class _ResetDataButton extends ConsumerWidget {
  const _ResetDataButton({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dangerColor =
        isDark ? AppColorTokens.debitDark : AppColorTokens.debitLight;

    return GestureDetector(
      onTap: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete all local data?'),
            content: const Text(
              'This permanently wipes all local transactions, categories, and learned rules from this device. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: dangerColor,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete Everything'),
              ),
            ],
          ),
        );
        if (confirm == true && context.mounted) {
          await ref.read(appDataResetServiceProvider).deleteEverything();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('All local data has been reset.')),
            );
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: dangerColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.bloomCard),
          border: Border.all(
            color: dangerColor.withValues(alpha: 0.3),
          ),
        ),
        child: Center(
          child: Text(
            'Delete all local data',
            style: AppTheme.bloomDisplay(
              14,
              FontWeight.w600,
              color: dangerColor,
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../../intelligence/llm/llm_model_status.dart';
import 'ai_model_controller.dart';

const aiModelPrivacyNote =
    'Downloaded once from Hugging Face; all processing stays on your device.';

/// Body of the Settings "ON-DEVICE AI" section.
class AiModelSectionBody extends ConsumerWidget {
  const AiModelSectionBody({super.key, required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiModelControllerProvider);
    final controller = ref.read(aiModelControllerProvider.notifier);
    final status = state.status;
    final primary =
        isDark ? AppColorTokens.bloomDarkTextPrimary : AppColorTokens.ink;
    final tertiary = isDark
        ? AppColorTokens.bloomDarkTextTertiary
        : AppColorTokens.inkTertiary;
    final secondary = isDark
        ? AppColorTokens.bloomDarkTextSecondary
        : AppColorTokens.inkSecondary;

    final name = status?.displayName ?? 'On-device AI model';
    final sizeText = status == null || status.sizeBytes <= 0
        ? null
        : formatModelSize(status.sizeBytes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModelHeader(
          icon: Icons.psychology_outlined,
          title: name,
          subtitle:
              [if (sizeText != null) sizeText, _phaseLabel(state)].join(' · '),
          isDark: isDark,
        ),
        const SizedBox(height: AppSpacing.sm),
        _llmBody(context, state, controller, status, primary, secondary),
        if (state.error != null)
          _Message(
            key: const ValueKey('ai_model_error'),
            text: state.error!,
            isDark: isDark,
          ),
        const SizedBox(height: AppSpacing.md),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.md),
        _EmbedderRow(isDark: isDark),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline_rounded, size: 16, color: tertiary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                aiModelPrivacyNote,
                key: const ValueKey('ai_model_privacy_note'),
                style: AppTheme.bloomDisplay(
                  12,
                  FontWeight.w400,
                  color: tertiary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _phaseLabel(AiModelState state) => switch (state.phase) {
        AiModelPhase.loading => 'Checking…',
        AiModelPhase.notDownloaded => 'Not downloaded',
        AiModelPhase.downloading => state.progress == null
            ? 'Downloading'
            : 'Downloading ${(state.progress! * 100).floor()}%',
        AiModelPhase.verifying => 'Verifying',
        AiModelPhase.installed => 'Installed',
        AiModelPhase.unsupported => 'Not supported on this device',
      };

  Widget _llmBody(
    BuildContext context,
    AiModelState state,
    AiModelController controller,
    LlmModelStatus? status,
    Color primary,
    Color secondary,
  ) {
    switch (state.phase) {
      case AiModelPhase.loading:
        return const SizedBox.shrink();
      case AiModelPhase.notDownloaded:
        return _ActionButton(
          key: const ValueKey('ai_model_download'),
          icon: Icons.download_rounded,
          label: 'Download AI model',
          filled: true,
          onPressed: () async {
            final ok = await confirmModelDownload(
              context,
              name: status!.displayName,
              sizeBytes: status.sizeBytes,
              source: 'Hugging Face',
            );
            if (ok) await controller.startDownload();
          },
        );
      case AiModelPhase.downloading:
      case AiModelPhase.verifying:
        final verifying = state.phase == AiModelPhase.verifying;
        final progress = verifying ? null : state.progress;
        final downloaded = status?.downloadedBytes ?? 0;
        final total = status?.sizeBytes ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              key: const ValueKey('ai_model_progress'),
              value: progress == 0 ? null : progress,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              color: AppColorTokens.violetPrimary,
              backgroundColor: isDark
                  ? AppColorTokens.bloomDarkTrack
                  : AppColorTokens.bloomChip,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              verifying
                  ? 'Checking the download is intact…'
                  : total > 0
                      ? '${formatModelSize(downloaded)} of '
                          '${formatModelSize(total)}'
                      : 'Downloading…',
              style: AppTheme.bloomDisplay(
                12,
                FontWeight.w500,
                color: secondary,
              ),
            ),
            if (!verifying)
              _ActionButton(
                key: const ValueKey('ai_model_cancel'),
                icon: Icons.close_rounded,
                label: 'Cancel',
                onPressed: controller.cancelDownload,
              ),
          ],
        );
      case AiModelPhase.installed:
        return _ActionButton(
          key: const ValueKey('ai_model_delete'),
          icon: Icons.delete_outline_rounded,
          label: 'Delete model',
          onPressed: () async {
            final ok = await _confirm(
              context,
              title: 'Delete AI model?',
              body: 'This frees ${formatModelSize(status!.sizeBytes)}. The '
                  'assistant falls back to keyword search until you '
                  'download it again.',
              action: 'Delete',
            );
            if (ok) await controller.deleteModel();
          },
        );
      case AiModelPhase.unsupported:
        return _Message(
          key: const ValueKey('ai_model_unsupported'),
          text: aiSupportReasonCopy(
            status?.supportReason ?? LlmSupportReason.unknown,
          ),
          isDark: isDark,
        );
    }
  }
}

/// Asks the user to confirm a network model download. Returns `true` on yes.
Future<bool> confirmModelDownload(
  BuildContext context, {
  required String name,
  required int sizeBytes,
  required String source,
}) {
  final size = sizeBytes > 0 ? formatModelSize(sizeBytes) : 'a large file';
  return _confirm(
    context,
    title: 'Download $name?',
    body: 'This downloads $size once from $source over your internet '
        'connection. Wi-Fi is recommended. After that, all processing '
        'stays on your device.',
    action: 'Download',
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final result = await showBloomAlertDialog<bool>(
    context: context,
    title: title,
    content: Text(body),
    actions: [
      Builder(
        builder: (dialogContext) => TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
      ),
      Builder(
        builder: (dialogContext) => FilledButton(
          key: const ValueKey('ai_model_confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(action),
        ),
      ),
    ],
  );
  return result ?? false;
}

class _EmbedderRow extends ConsumerWidget {
  const _EmbedderRow({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiModelControllerProvider);
    final controller = ref.read(aiModelControllerProvider.notifier);
    final installed = state.embedderInstalled;
    final label = state.embedderBusy
        ? 'Working…'
        : installed == null
            ? 'Checking…'
            : installed
                ? 'Installed'
                : 'Not downloaded';
    final size = formatModelSize(embedderModelSizeBytes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModelHeader(
          icon: Icons.hub_outlined,
          title: 'Merchant matching model',
          subtitle: '$size · $label',
          isDark: isDark,
        ),
        if (!state.embedderBusy && installed != null)
          installed
              ? _ActionButton(
                  key: const ValueKey('embedder_delete'),
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete model',
                  onPressed: () async {
                    final ok = await _confirm(
                      context,
                      title: 'Delete merchant matching model?',
                      body: 'Merchant names will be matched by exact text '
                          'until you download it again.',
                      action: 'Delete',
                    );
                    if (ok) await controller.deleteEmbedder();
                  },
                )
              : _ActionButton(
                  key: const ValueKey('embedder_download'),
                  icon: Icons.download_rounded,
                  label: 'Download',
                  onPressed: () async {
                    final ok = await confirmModelDownload(
                      context,
                      name: 'merchant matching model',
                      sizeBytes: embedderModelSizeBytes,
                      source: "Google's model storage",
                    );
                    if (ok) await controller.downloadEmbedder();
                  },
                ),
        if (state.embedderError != null)
          _Message(text: state.embedderError!, isDark: isDark),
      ],
    );
  }
}

class _ModelHeader extends StatelessWidget {
  const _ModelHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: isDark
              ? AppColorTokens.bloomDarkTextSecondary
              : AppColorTokens.inkSecondary,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTheme.bloomDisplay(
                  14,
                  FontWeight.w600,
                  color: isDark
                      ? AppColorTokens.bloomDarkTextPrimary
                      : AppColorTokens.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
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
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    const style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size(AppSizes.minTouchTarget, AppSizes.minTouchTarget),
      ),
    );
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: filled
          ? FilledButton.icon(
              style: style,
              onPressed: onPressed,
              icon: Icon(icon, size: 18),
              label: Text(label),
            )
          : TextButton.icon(
              style: style,
              onPressed: onPressed,
              icon: Icon(icon, size: 18),
              label: Text(label),
            ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({super.key, required this.text, required this.isDark});

  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Text(
        text,
        style: AppTheme.bloomDisplay(
          12,
          FontWeight.w500,
          color: isDark ? AppColorTokens.errorDark : AppColorTokens.errorLight,
        ),
      ),
    );
  }
}

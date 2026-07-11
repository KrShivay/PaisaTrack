import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/paisa_colors.dart';

/// Designed empty state: brand illustration + one-line explanation + one
/// optional action (docs/design-system.md §5). Replaces bare centered strings.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.illustration,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  /// Asset path from [AppIllustrations]. Rendered at hero size (§6).
  final String illustration;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              illustration,
              width: 96,
              height: 96,
              // Illustrations are decorative; the title/message carry meaning.
              excludeFromSemantics: true,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Warning-tinted "Notice" recipe (§9) for recoverable load failures. Uses the
/// warning hue, not error red, unless something truly failed irrecoverably.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paisa = PaisaColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: paisa.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, color: paisa.warning),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: AppSpacing.md),
                TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder list shown while transactions load. Subtle pulse when animations
/// are enabled, static otherwise (respects MediaQuery.disableAnimations, §7).
class ListLoadingSkeleton extends StatefulWidget {
  const ListLoadingSkeleton({super.key, this.rows = 6});

  final int rows;

  @override
  State<ListLoadingSkeleton> createState() => _ListLoadingSkeletonState();
}

class _ListLoadingSkeletonState extends State<ListLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final animate = !MediaQuery.of(context).disableAnimations;
    final base = theme.colorScheme.surfaceContainerHighest;

    Widget block(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        );

    final content = ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: widget.rows,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, index) => ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: base, shape: BoxShape.circle),
        ),
        title: Align(alignment: Alignment.centerLeft, child: block(140, 12)),
        subtitle: Align(alignment: Alignment.centerLeft, child: block(80, 10)),
        trailing: block(64, 14),
      ),
    );

    if (!animate) return Semantics(label: 'Loading', child: content);
    return Semantics(
      label: 'Loading',
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.4, end: 0.9).animate(_controller),
        child: content,
      ),
    );
  }
}

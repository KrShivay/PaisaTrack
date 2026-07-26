import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../data/db/database_provider.dart';

/// Screen shown when the database fails to open due to a non-key-loss error
/// (e.g. transient I/O, plugin failure). Offers retry and last-resort reset.
class DatabaseErrorScreen extends ConsumerStatefulWidget {
  const DatabaseErrorScreen({super.key, required this.error});

  final Object error;

  @override
  ConsumerState<DatabaseErrorScreen> createState() =>
      _DatabaseErrorScreenState();
}

class _DatabaseErrorScreenState extends ConsumerState<DatabaseErrorScreen> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    ref.invalidate(appDatabaseProvider);
    // The provider will re-evaluate and the parent PaisaTrackApp will rebuild.
    // If it succeeds, this screen will be replaced with the home shell.
    // If it fails again, this screen will remain.
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Database Error'),
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
                Icons.error_outline_rounded,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Could Not Open Database',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'A temporary error prevented the database from opening. '
                'This is usually caused by a system glitch and can be resolved by retrying.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .errorContainer
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.error.toString(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (_busy)
                const Center(child: CircularProgressIndicator())
              else ...[
                FilledButton.icon(
                  key: const ValueKey('db_error_retry_button'),
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

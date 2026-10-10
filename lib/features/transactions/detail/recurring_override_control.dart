import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../data/repositories/recurring_override_repository.dart';

/// "Recurring payment" control: Auto / Recurring / One-time.
class RecurringOverrideControl extends ConsumerWidget {
  const RecurringOverrideControl({super.key, required this.txnId});

  final String txnId;

  static String _confirmation(RecurringOverride value) => switch (value) {
        RecurringOverride.automatic => 'Recurring payment set to automatic',
        RecurringOverride.recurring => 'Marked as recurring payment',
        RecurringOverride.notRecurring => 'Marked as one-time payment',
      };

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    RecurringOverride value,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repository =
          await ref.read(recurringOverrideRepositoryProvider.future);
      await repository.setOverride(txnId, value);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(_confirmation(value))));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update recurring setting.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark
        ? AppColorTokens.bloomDarkTextTertiary
        : AppColorTokens.inkTertiary;
    final current =
        ref.watch(transactionRecurringOverrideProvider(txnId)).valueOrNull ??
            RecurringOverride.automatic;
    final detected = current == RecurringOverride.automatic
        ? ref.watch(transactionDetectedRecurringProvider(txnId)).valueOrNull
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recurring payment',
          style: AppTheme.bloomDisplay(11, FontWeight.w500, color: labelColor),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<RecurringOverride>(
            key: const ValueKey('recurring_override_control'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: RecurringOverride.automatic,
                label: _SegmentLabel('Auto'),
              ),
              ButtonSegment(
                value: RecurringOverride.recurring,
                label: _SegmentLabel('Recurring'),
              ),
              ButtonSegment(
                value: RecurringOverride.notRecurring,
                label: _SegmentLabel('One-time'),
              ),
            ],
            selected: {current},
            onSelectionChanged: (selection) =>
                _select(context, ref, selection.first),
          ),
        ),
        if (detected != null) ...[
          const SizedBox(height: 4),
          Text(
            detected ? 'Detected as recurring' : 'Not detected as recurring',
            style:
                AppTheme.bloomDisplay(11, FontWeight.w400, color: labelColor),
          ),
        ],
      ],
    );
  }
}

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text, maxLines: 1),
      );
}

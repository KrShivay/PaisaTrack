import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/paisa_colors.dart';
import '../../core/widgets/app_state_views.dart';
import '../../data/db/database.dart';
import '../../data/db/database_provider.dart';

/// Non-dismissed insights for the current UTC reporting month.
final activeInsightsProvider = StreamProvider<List<Insight>>((ref) {
  final now = DateTime.now().toUtc();
  final period = '${now.year}-${now.month.toString().padLeft(2, '0')}';
  final databaseAsync = ref.watch(appDatabaseProvider);
  return databaseAsync.when(
    data: (database) => (database.select(database.insights)
          ..where(
            (row) => row.dismissed.equals(false) & row.period.like('$period%'),
          )
          ..orderBy([
            (row) => OrderingTerm.desc(row.period),
            (row) => OrderingTerm.asc(row.kind),
          ]))
        .watch(),
    loading: () => const Stream<List<Insight>>.empty(),
    error: (error, stackTrace) =>
        Stream<List<Insight>>.error(error, stackTrace),
  );
});

/// Monthly report rendered only from deterministic aggregate insight payloads.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(activeInsightsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: switch (insights) {
        AsyncData(:final value) when value.isEmpty => const EmptyStateView(
            illustration: AppIllustrations.investmentGrowth,
            title: 'No insights yet',
            message:
                'Your monthly report will appear as recurring patterns and spending changes are detected.',
          ),
        AsyncData(:final value) => _InsightsList(
            insights: value,
            onDismiss: (id) => _dismiss(context, ref, id),
          ),
        AsyncError() => const ErrorStateView(
            message: 'Could not load your insights.',
          ),
        _ => const ListLoadingSkeleton(rows: 4),
      },
    );
  }

  Future<void> _dismiss(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final database = await ref.read(appDatabaseProvider.future);
      await (database.update(database.insights)
            ..where((row) => row.id.equals(id)))
          .write(const InsightsCompanion(dismissed: Value(true)));
      messenger.showSnackBar(
        const SnackBar(content: Text('Insight dismissed')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not dismiss insight')),
      );
    }
  }
}

class _InsightsList extends StatelessWidget {
  const _InsightsList({required this.insights, required this.onDismiss});

  final List<Insight> insights;
  final ValueChanged<String> onDismiss;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final month = MaterialLocalizations.of(context).formatMonthYear(now);
    return ListView.separated(
      padding: AppSpacing.screen,
      itemCount: insights.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              '$month report',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          );
        }
        final insight = insights[index - 1];
        return _InsightCard(
          insight: insight,
          onDismiss: () => onDismiss(insight.id),
        );
      },
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight, required this.onDismiss});

  final Insight insight;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final presentation = _presentation(insight);
    final theme = Theme.of(context);
    final color = presentation.warning
        ? PaisaColors.of(context).warning
        : theme.colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
              ),
              child: Icon(presentation.icon, color: color, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    presentation.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    presentation.body,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Dismiss ${presentation.title}',
              onPressed: onDismiss,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

class _Presentation {
  const _Presentation({
    required this.title,
    required this.body,
    required this.icon,
    this.warning = false,
  });

  final String title;
  final String body;
  final IconData icon;
  final bool warning;
}

_Presentation _presentation(Insight insight) {
  final payload = _payload(insight.payloadJson);
  return switch (insight.kind) {
    'forecast' => _Presentation(
        title: 'Month-end forecast',
        body:
            'Projected spend is ${_money(payload, 'projected_spend')}, ${_percent(payload, 'deviation_fraction')} versus your recent monthly average.',
        icon: Icons.query_stats,
      ),
    'anomaly' => _Presentation(
        title: 'Unusual spending detected',
        body:
            '${_money(payload, 'aggregate')} was recorded, above the usual ${_money(payload, 'threshold')} threshold.',
        icon: Icons.warning_amber_outlined,
        warning: true,
      ),
    'duplicate_subscription' => _Presentation(
        title: 'Possible duplicate subscription',
        body:
            '${_text(payload, 'label', fallback: 'One merchant')} has multiple active plans totalling about ${_money(payload, 'monthly_total')} per month.',
        icon: Icons.content_copy_outlined,
        warning: true,
      ),
    'fees_total' => _Presentation(
        title: 'Fees and penalties',
        body:
            '${_money(payload, 'total')} across ${_number(payload, 'count').round()} charges this month.',
        icon: Icons.request_quote_outlined,
        warning: true,
      ),
    'price_creep' => _Presentation(
        title: 'Recurring price increased',
        body:
            '${_text(payload, 'label')} is now ${_money(payload, 'last_amount')}; expected amount was ${_money(payload, 'expected_amount')}.',
        icon: Icons.trending_up,
        warning: true,
      ),
    'category_delta' => _Presentation(
        title: '${_text(payload, 'category_name')} changed',
        body:
            'Spending is ${_percent(payload, 'delta_fraction')} versus last month (${_money(payload, 'current_total')} now).',
        icon: Icons.compare_arrows,
      ),
    'missed_autopay' => _Presentation(
        title: 'Possible missed payment',
        body:
            '${_text(payload, 'label')} was expected on ${_date(payload, 'next_expected_date')}.',
        icon: Icons.event_busy_outlined,
        warning: true,
      ),
    _ => const _Presentation(
        title: 'Financial insight',
        body: 'A new aggregate pattern was detected in your local data.',
        icon: Icons.lightbulb_outline,
      ),
  };
}

Map<String, Object?> _payload(String source) {
  try {
    final decoded = jsonDecode(source);
    return decoded is Map<String, Object?> ? decoded : const {};
  } on FormatException {
    return const {};
  }
}

num _number(Map<String, Object?> payload, String key) =>
    payload[key] is num ? payload[key]! as num : 0;

String _money(Map<String, Object?> payload, String key) =>
    formatInr(_number(payload, key).toDouble());

String _percent(Map<String, Object?> payload, String key) {
  final value = _number(payload, key).toDouble() * 100;
  final sign = value > 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(0)}%';
}

String _text(
  Map<String, Object?> payload,
  String key, {
  String fallback = 'This item',
}) =>
    payload[key] is String && (payload[key]! as String).trim().isNotEmpty
        ? payload[key]! as String
        : fallback;

String _date(Map<String, Object?> payload, String key) {
  final parsed = DateTime.tryParse(_text(payload, key, fallback: ''));
  if (parsed == null) return 'the expected date';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${parsed.day} ${months[parsed.month - 1]}';
}

import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/paisa_colors.dart';
import '../../core/widgets/app_state_views.dart';
import '../../data/db/database.dart';
import '../../data/db/database_provider.dart';
import '../assistant/assistant_screen.dart';
import '../dashboard/dashboard_providers.dart';
import '../recurring/recurring_screen.dart';
import '../settings/settings_screen.dart';

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
      appBar: AppBar(
        title: const Text('Insights'),
        actions: [
          IconButton(
            tooltip: 'Recurring',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const RecurringScreen(),
              ),
            ),
            icon: const Icon(Icons.autorenew_outlined),
          ),
          IconButton(
            tooltip: 'Ask PaisaTrack',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AssistantScreen(),
              ),
            ),
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen(),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: _InsightsOverview(
        insights: insights,
        onDismiss: (id) => _dismiss(context, ref, id),
        onOpenRecurring: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const RecurringScreen()),
        ),
      ),
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

class _InsightsOverview extends ConsumerWidget {
  const _InsightsOverview({
    required this.insights,
    required this.onDismiss,
    required this.onOpenRecurring,
  });

  final AsyncValue<List<Insight>> insights;
  final ValueChanged<String> onDismiss;
  final VoidCallback onOpenRecurring;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(monthDirectionTotalsProvider);
    final comparison = ref.watch(monthOverMonthSpendProvider);
    final categories = ref.watch(categoryBreakdownProvider);
    final merchants = ref.watch(topMerchantsProvider);
    final hasTransactions = totals.debitTotal > 0 || totals.creditTotal > 0;
    final generated = insights.valueOrNull ?? const <Insight>[];
    final theme = Theme.of(context);
    final now = DateTime.now();
    final month = MaterialLocalizations.of(context).formatMonthYear(now);

    return ListView(
      padding: AppSpacing.screen,
      children: [
        Text('$month overview', style: theme.textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.md),
        if (hasTransactions) ...[
          _BaselineSummary(
            spent: totals.debitTotal,
            received: totals.creditTotal,
            comparison: comparison,
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text('Spending by category', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final category in categories.take(5))
              _BaselineRow(
                label: category.name,
                value: formatInr(category.total),
                supporting:
                    '${(category.share * 100).toStringAsFixed(0)}% of spending',
              ),
          ],
          if (merchants.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text('Top merchants', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final merchant in merchants.take(3))
              _BaselineRow(
                label: merchant.name,
                value: formatInr(merchant.total),
                supporting:
                    '${merchant.count} transaction${merchant.count == 1 ? '' : 's'}',
              ),
          ],
          const SizedBox(height: AppSpacing.lg),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.autorenew_outlined),
            title: const Text('Recurring activity'),
            subtitle: const Text('Subscriptions, bills, EMIs and income'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenRecurring,
          ),
        ] else if (generated.isEmpty)
          const EmptyStateView(
            illustration: AppIllustrations.spendAnalysis,
            title: 'Insights start with your transactions',
            message:
                'Monthly summaries and comparisons will appear after financial messages or manual transactions are added.',
          ),
        const SizedBox(height: AppSpacing.lg),
        Text('Changes to know about', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        if (insights.isLoading)
          const SizedBox(height: 180, child: ListLoadingSkeleton(rows: 2))
        else if (insights.hasError)
          const ErrorStateView(
            message:
                'Some generated insights could not load. Your saved transactions remain safe.',
          )
        else if (generated.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No unusual changes detected'),
                SizedBox(height: AppSpacing.xs),
                Text(
                  'Your spending is currently consistent with the available history. More detailed insights will appear as PaisaTrack learns your patterns.',
                ),
              ],
            ),
          )
        else
          for (final insight in generated) ...[
            _InsightCard(
              insight: insight,
              onDismiss: () => onDismiss(insight.id),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
      ],
    );
  }
}

class _BaselineSummary extends StatelessWidget {
  const _BaselineSummary({
    required this.spent,
    required this.received,
    required this.comparison,
  });

  final double spent;
  final double received;
  final MonthOverMonthSpend comparison;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = comparison.pctChange;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Monthly spending', style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            formatInr(spent),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: AppTheme.tabularFigures,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Received ${formatInr(received)}'),
          if (change != null)
            Text(
              '${change.abs() * 100 < 0.5 ? 'About the same as' : '${(change.abs() * 100).toStringAsFixed(0)}% ${change < 0 ? 'lower' : 'higher'} than'} last month',
            ),
        ],
      ),
    );
  }
}

class _BaselineRow extends StatelessWidget {
  const _BaselineRow({
    required this.label,
    required this.value,
    required this.supporting,
  });

  final String label;
  final String value;
  final String supporting;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(supporting),
      trailing: Text(
        value,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontFeatures: AppTheme.tabularFigures,
            ),
      ),
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
    'narrative' => _Presentation(
        title: 'Monthly summary',
        body: _text(payload, 'body'),
        icon: Icons.auto_awesome_outlined,
      ),
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

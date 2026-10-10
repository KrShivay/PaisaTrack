import 'dart:async';
import 'package:drift/drift.dart' show Expression, TableUpdateQuery;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clock.dart';
import '../../core/financial_calendar.dart';
import '../../core/format.dart';
import '../../core/undo/undo_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/category_visuals.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../../data/db/database.dart';
import '../../data/db/database_provider.dart';
import '../../data/repositories/trends_inbox_repository.dart';
import '../../intelligence/claim.dart';
import '../../intelligence/derived_reads_service.dart';
import '../dashboard/dashboard_providers.dart';
import '../dashboard/period_selection_sheet.dart';
import '../dashboard/source_currency_activity.dart';
import '../recurring/recurring_screen.dart';
import '../transactions/transactions_screen.dart';
import 'trends_history_screen.dart';

/// Stream of non-dismissed precomputed insights for the current period.
final activeInsightsProvider = StreamProvider<List<Insight>>((ref) {
  final dbAsync = ref.watch(appDatabaseProvider);
  final period = ref.watch(dashboardPeriodProvider);
  final calendar = ref.watch(financialCalendarProvider);
  final monthKey = insightMonthKeyForPeriod(period);

  return dbAsync.when(
    data: (db) => Stream.multi((controller) {
      var active = true;
      var revision = 0;
      Timer? debounce;
      Future<void> emitInsights() async {
        final requestedRevision = ++revision;
        final rows = await (db.select(db.insights)
              ..where(
                (i) => Expression.and([
                  i.period.equals(monthKey),
                  i.dismissed.equals(false),
                ]),
              ))
            .get();
        final insights = await freshClaims(
          db,
          rows,
          calendar: calendar,
        );
        if (active && requestedRevision == revision) controller.add(insights);
      }

      void scheduleInsights({bool immediate = false}) {
        debounce?.cancel();
        if (immediate) {
          unawaited(emitInsights());
        } else {
          revision++;
          debounce = Timer(derivedReadsDebounceDuration, () {
            unawaited(emitInsights());
          });
        }
      }

      scheduleInsights(immediate: true);
      final updates = db
          .tableUpdates(
            TableUpdateQuery.onAllTables([
              db.insights,
              db.transactions,
              db.categories,
              db.paymentSources,
            ]),
          )
          .listen((_) => scheduleInsights());
      controller.onCancel = () {
        active = false;
        debounce?.cancel();
        return updates.cancel();
      };
    }),
    loading: () => const Stream<List<Insight>>.empty(),
    error: (err, st) => Stream<List<Insight>>.error(err, st),
  );
});

final trendsInboxItemsProvider = StreamProvider<List<TrendsInboxItem>>((ref) {
  final claimsAsync = ref.watch(activeInsightsProvider);
  if (!claimsAsync.hasValue || claimsAsync.isLoading) {
    return Stream.value(const []);
  }
  final database = ref.watch(appDatabaseProvider.future);
  final period = ref.watch(dashboardPeriodProvider);
  final selectedPeriod = insightMonthKeyForPeriod(period);
  if (claimsAsync.requireValue.any((claim) => claim.period != selectedPeriod)) {
    return Stream.value(const []);
  }
  final claims = claimsAsync.requireValue
      .where((claim) => claim.period == selectedPeriod)
      .toList(growable: false);
  return Stream.fromFuture(
    database.then(
      (db) => TrendsInboxRepository(db).reconcile(
        period: selectedPeriod,
        freshClaims: claims,
      ),
    ),
  );
});

/// Every retained inbox item across periods, including cleared and Later.
///
/// Watches [trendsInboxItemsProvider] so any mutation that invalidates the
/// live inbox also refreshes the history.
final trendsInboxHistoryProvider =
    FutureProvider.autoDispose<List<TrendsInboxItem>>((ref) async {
  ref.watch(trendsInboxItemsProvider);
  final database = await ref.watch(appDatabaseProvider.future);
  return TrendsInboxRepository(database).readAll();
});

/// Opens the evidence transactions behind an inbox item.
Future<void> openTrendsInboxEvidence(
  BuildContext context,
  TrendsInboxItem item,
) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TransactionsScreen(
          initialTransactionIds: item.claim.evidenceIds.toSet(),
          initialEvidenceTotalCount: item.claim.evidenceCount,
        ),
      ),
    );

void openTrendsHistory(BuildContext context) {
  unawaited(
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const TrendsHistoryScreen()),
    ),
  );
}

final markTrendsInboxSeenProvider =
    Provider<Future<void> Function(Iterable<String>)>((ref) {
  return (keys) async {
    final database = await ref.read(appDatabaseProvider.future);
    final repository = TrendsInboxRepository(database);
    for (final key in keys) {
      await repository.markSeen(key);
    }
  };
});

final claimDisplayNamesProvider =
    FutureProvider<ClaimDisplayNames>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return loadClaimDisplayNames(db);
});

final trendsInboxEnabledProvider = Provider<bool>((ref) => inboxEnabled);

String insightMonthKeyForPeriod(DashboardPeriod period) =>
    period.calendar.monthKey(period.start);

/// Redesigned Bloom Trends (Insights) screen with scoped period picker,
/// narrative insight cards with dismissal, 6-month bar chart, MoM comparison,
/// category share breakdown, and top merchants.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final period = ref.watch(dashboardPeriodProvider);
    final aggregateAsync = ref.watch(dashboardAggregateProvider);
    final claimCategoryNames =
        ref.watch(claimDisplayNamesProvider).valueOrNull?.categories ??
            const <String, String>{};
    final sixMonthTrend = ref.watch(sixMonthTrendProvider);
    final mom = ref.watch(monthOverMonthSpendProvider);
    final totals = ref.watch(monthDirectionTotalsProvider);
    final categories = ref.watch(categoryBreakdownProvider);
    final merchants = ref.watch(topMerchantsProvider);
    final activeInsightsAsync = ref.watch(activeInsightsProvider);
    final insights = activeInsightsAsync.valueOrNull ?? const [];
    final useInbox = ref.watch(trendsInboxEnabledProvider);
    final inboxAsync = useInbox ? ref.watch(trendsInboxItemsProvider) : null;
    final inboxItems = inboxAsync?.valueOrNull ?? const <TrendsInboxItem>[];
    final compactHeader = MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(1) >= 1.5;

    return Scaffold(
      backgroundColor:
          isDark ? AppColorTokens.bloomDarkBase : AppColorTokens.bloomBase,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            BloomBottomInset.contentPadding(context),
          ),
          children: [
            // Top Header: Title + Period Chip + Recurring button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Trends',
                        style: AppTheme.bloomDisplay(
                          22,
                          FontWeight.w700,
                          letterSpacing: -0.03,
                          color: isDark
                              ? AppColorTokens.bloomDarkTextPrimary
                              : AppColorTokens.ink,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Spending patterns & analytics',
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
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    showBloomModalSheet(
                      context: context,
                      builder: (context) => const BloomDatePeriodSheet(),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColorTokens.bloomDarkCard
                          : AppColorTokens.bloomChip,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: compactHeader
                        ? Tooltip(
                            message: 'Period: ${period.label}',
                            child: const SizedBox(
                              width: 48,
                              height: 48,
                              child: Icon(Icons.calendar_month_rounded),
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_month_rounded,
                                size: 14,
                                color: isDark
                                    ? AppColorTokens.bloomDarkTextSecondary
                                    : AppColorTokens.inkSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                period.label,
                                style: AppTheme.bloomDisplay(
                                  11,
                                  FontWeight.w600,
                                  color: isDark
                                      ? AppColorTokens.bloomDarkTextSecondary
                                      : AppColorTokens.inkSecondary,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const RecurringScreen(),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColorTokens.bloomDarkCard
                          : AppColorTokens.bloomChip,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: compactHeader
                        ? const Tooltip(
                            message: 'Recurring transactions',
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: Icon(Icons.autorenew_rounded),
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.autorenew_rounded,
                                size: 14,
                                color: isDark
                                    ? AppColorTokens.bloomDarkTextSecondary
                                    : AppColorTokens.inkSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Recurring',
                                style: AppTheme.bloomDisplay(
                                  11,
                                  FontWeight.w600,
                                  color: isDark
                                      ? AppColorTokens.bloomDarkTextSecondary
                                      : AppColorTokens.inkSecondary,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (useInbox) ...[
              _TrendsInboxSection(
                items: inboxItems,
                isDark: isDark,
                categoryNames: claimCategoryNames,
              ),
              const SizedBox(height: 20),
            ] else if (insights.isNotEmpty) ...[
              // Existing fresh-claim feed is the inbox rollback path.
              for (final insight in insights) ...[
                _NarrativeInsightCard(
                  insight: insight,
                  isDark: isDark,
                  categoryNames: claimCategoryNames,
                  onDismiss: () async {
                    final db = await ref.read(appDatabaseProvider.future);
                    await TrendsInboxRepository(db).clearClaim(insight.id);
                  },
                  onWhy: () async {
                    final claim = const ClaimValidator().parse(insight);
                    if (claim == null || !context.mounted) return;
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => TransactionsScreen(
                          initialTransactionIds: claim.evidenceIds.toSet(),
                          initialEvidenceTotalCount: claim.evidenceCount,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 12),
            ],

            // Analytics sections are driven only by the SQL aggregate; loading
            // and error stay distinct from real data (never the bounded feed).
            ...aggregateAsync.when(
              data: (_) => [
                Text(
                  'INR ANALYTICS',
                  style: AppTheme.bloomDisplay(
                    11,
                    FontWeight.w600,
                    letterSpacing: 0.12,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextSecondary
                        : AppColorTokens.inkSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Trend, month-over-month, category, and merchant totals use INR. Other source currencies are listed separately below.',
                  style: AppTheme.bloomDisplay(
                    12,
                    FontWeight.w400,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextTertiary
                        : AppColorTokens.inkTertiary,
                  ),
                ),
                const SizedBox(height: 12),
                const BloomSourceCurrencyActivity(),
                const SizedBox(height: 20),
                // 6-Month Spend Bar Chart Card
                _SixMonthBarChartCard(
                  trend: sixMonthTrend.requireValue,
                  isDark: isDark,
                ),
                const SizedBox(height: 20),

                // Month-over-Month Comparison Card
                _MoMComparisonCard(
                  mom: mom.requireValue,
                  currentSpend: totals.requireValue.debitTotal,
                  period: period,
                  isDark: isDark,
                ),
                const SizedBox(height: 24),

                // Category Breakdown Section
                _CategoryBreakdownSection(
                  categories: categories.requireValue,
                  isDark: isDark,
                ),
                const SizedBox(height: 24),

                // Top Merchants Section
                _TopMerchantsSection(
                  merchants: merchants.requireValue,
                  isDark: isDark,
                ),
              ],
              loading: () => [_analyticsPlaceholder(isDark, isError: false)],
              error: (_, __) => [
                _analyticsPlaceholder(
                  isDark,
                  isError: true,
                  onRetry: () => ref.invalidate(dashboardAggregateProvider),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendsInboxSection extends ConsumerStatefulWidget {
  const _TrendsInboxSection({
    required this.items,
    required this.isDark,
    required this.categoryNames,
  });

  final List<TrendsInboxItem> items;
  final bool isDark;
  final Map<String, String> categoryNames;

  @override
  ConsumerState<_TrendsInboxSection> createState() =>
      _TrendsInboxSectionState();
}

class _TrendsInboxSectionState extends ConsumerState<_TrendsInboxSection> {
  @override
  Widget build(BuildContext context) {
    final visible = widget.items
        .where(
          (item) => item.isCurrent && item.state != TrendsInboxState.cleared,
        )
        .toList(growable: false);
    final historyCount =
        ref.watch(trendsInboxHistoryProvider).valueOrNull?.length ?? 0;
    if (visible.isEmpty) {
      if (historyCount == 0) return const SizedBox.shrink();
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => openTrendsHistory(context),
          icon: const Icon(Icons.history_rounded, size: 18),
          label: Text('View insight history ($historyCount)'),
        ),
      );
    }
    final repository = ref.read(appDatabaseProvider).valueOrNull == null
        ? null
        : TrendsInboxRepository(ref.read(appDatabaseProvider).requireValue);
    final period = insightMonthKeyForPeriod(
      ref.watch(dashboardPeriodProvider),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'INSIGHTS',
                style: AppTheme.bloomDisplay(
                  11,
                  FontWeight.w600,
                  letterSpacing: 0.12,
                  color: widget.isDark
                      ? AppColorTokens.bloomDarkTextSecondary
                      : AppColorTokens.inkSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => openTrendsHistory(context),
              child: const Text('History'),
            ),
            TextButton(
              onPressed: repository == null
                  ? null
                  : () async {
                      final undo = await repository.clearAll(period: period);
                      ref.invalidate(trendsInboxItemsProvider);
                      ref.read(undoControllerProvider.notifier).pushUndo(
                            UndoToken(
                              id: 'trends-inbox-clear-all',
                              message: 'Cleared Trends inbox',
                              undoAction: () async {
                                await repository.undoClearAll(undo);
                                ref.invalidate(trendsInboxItemsProvider);
                              },
                            ),
                          );
                    },
              child: const Text('Clear all'),
            ),
          ],
        ),
        for (final item in visible)
          Dismissible(
            key: ValueKey(item.key),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: AppColorTokens.violetPrimary,
              child: const Icon(Icons.delete_outline, color: Colors.white),
            ),
            onDismissed: (_) async {
              if (repository == null) return;
              await repository.clear(item.key);
              ref.invalidate(trendsInboxItemsProvider);
            },
            child: _TrendsInboxCard(
              item: item,
              isDark: widget.isDark,
              categoryNames: widget.categoryNames,
              onOpen: repository == null
                  ? null
                  : () async {
                      if (!context.mounted) return;
                      await openTrendsInboxEvidence(context, item);
                    },
              onMove: repository == null
                  ? null
                  : () async {
                      if (item.state == TrendsInboxState.moved) {
                        await repository.returnToSeen(item.key);
                      } else {
                        await repository.moveToLater(item.key);
                      }
                      ref.invalidate(trendsInboxItemsProvider);
                    },
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _TrendsInboxCard extends StatelessWidget {
  const _TrendsInboxCard({
    required this.item,
    required this.isDark,
    required this.categoryNames,
    required this.onOpen,
    required this.onMove,
  });

  final TrendsInboxItem item;
  final bool isDark;
  final Map<String, String> categoryNames;
  final VoidCallback? onOpen;
  final VoidCallback? onMove;

  @override
  Widget build(BuildContext context) {
    final display = const ClaimRenderer().render(
      item.claim,
      categoryNames: categoryNames,
    );
    if (display == null) return const SizedBox.shrink();
    final textColor =
        isDark ? AppColorTokens.bloomDarkTextPrimary : AppColorTokens.ink;
    final secondaryColor = isDark
        ? AppColorTokens.bloomDarkTextSecondary
        : AppColorTokens.inkSecondary;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomChip,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: onOpen,
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      foregroundColor: textColor,
                      padding: EdgeInsets.zero,
                    ),
                    child: Text(
                      display.title,
                      style: AppTheme.bloomDisplay(13, FontWeight.w600),
                    ),
                  ),
                ),
                if (item.state == TrendsInboxState.newItem)
                  const _InboxStateLabel('New'),
                if (item.state == TrendsInboxState.moved)
                  const _InboxStateLabel('Later'),
              ],
            ),
            Text(
              display.body,
              style: AppTheme.bloomDisplay(
                12,
                FontWeight.w400,
                color: secondaryColor,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onMove,
                child: Text(
                  item.state == TrendsInboxState.moved
                      ? 'Return'
                      : 'Move to later',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxStateLabel extends StatelessWidget {
  const _InboxStateLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Chip(
        label: Text(label),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
}

/// Loading/error placeholder for the analytics sections. Keeps loading and
/// failure visually distinct and never renders a fabricated number.
Widget _analyticsPlaceholder(
  bool isDark, {
  required bool isError,
  VoidCallback? onRetry,
}) {
  final border =
      isDark ? AppColorTokens.bloomDarkOutline : AppColorTokens.bloomHairline;
  final textColor = isDark
      ? AppColorTokens.bloomDarkTextSecondary
      : AppColorTokens.inkSecondary;
  return Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomChip,
      borderRadius: BorderRadius.circular(AppRadius.bloomCard),
      border: Border.all(color: border),
    ),
    child: isError
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: textColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Couldn't load spending analytics.",
                      style: AppTheme.bloomDisplay(
                        13,
                        FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child:
                    TextButton(onPressed: onRetry, child: const Text('Retry')),
              ),
            ],
          )
        : const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BloomSkeleton(height: 120, borderRadius: 12),
              SizedBox(height: 16),
              BloomSkeleton(height: 60, borderRadius: 12),
              SizedBox(height: 16),
              BloomSkeleton(height: 60, borderRadius: 12),
            ],
          ),
  );
}

class _NarrativeInsightCard extends StatelessWidget {
  const _NarrativeInsightCard({
    required this.insight,
    required this.isDark,
    required this.categoryNames,
    required this.onDismiss,
    required this.onWhy,
  });

  final Insight insight;
  final bool isDark;
  final Map<String, String> categoryNames;
  final VoidCallback onDismiss;
  final VoidCallback onWhy;

  @override
  Widget build(BuildContext context) {
    final bg = isDark
        ? AppColorTokens.violetPrimary.withValues(alpha: 0.16)
        : const Color(0xFFF3E8FF);
    final border = isDark
        ? AppColorTokens.violetPrimary.withValues(alpha: 0.3)
        : const Color(0xFFE9D5FF);

    final claim = const ClaimValidator().parse(insight);
    final display = claim == null
        ? null
        : const ClaimRenderer().render(
            claim,
            categoryNames: categoryNames,
          );
    if (display == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.bloomCard),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.auto_awesome,
            size: 20,
            color: isDark ? const Color(0xFFC084FC) : const Color(0xFF7E22CE),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  display.title,
                  style: AppTheme.bloomDisplay(
                    13,
                    FontWeight.w600,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextPrimary
                        : AppColorTokens.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  display.body,
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
          const SizedBox(width: 8),
          Column(
            children: [
              IconButton(
                tooltip: 'Why?',
                onPressed: onWhy,
                icon: const Icon(Icons.help_outline_rounded, size: 19),
              ),
              IconButton(
                tooltip: 'Dismiss insight',
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SixMonthBarChartCard extends StatelessWidget {
  const _SixMonthBarChartCard({
    required this.trend,
    required this.isDark,
  });

  final List<MonthPoint> trend;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard;
    final maxSpend = trend.fold<double>(
      1.0,
      (max, b) => b.spend > max ? b.spend : max,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.bloomCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SPEND TREND (LAST 6 MONTHS)',
            style: AppTheme.bloomDisplay(
              11,
              FontWeight.w600,
              letterSpacing: 0.1,
              color: isDark
                  ? AppColorTokens.bloomDarkTextTertiary
                  : AppColorTokens.inkTertiary,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 140,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final largeText =
                    MediaQuery.textScalerOf(context).scale(1) >= 1.5;
                final chartWidth = largeText && constraints.maxWidth < 540
                    ? 540.0
                    : constraints.maxWidth;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: chartWidth,
                    height: 140,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (int i = 0; i < trend.length; i++)
                          _BarColumn(
                            bucket: trend[i],
                            isCurrent: i == trend.length - 1,
                            maxSpend: maxSpend,
                            isDark: isDark,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BarColumn extends StatelessWidget {
  const _BarColumn({
    required this.bucket,
    required this.isCurrent,
    required this.maxSpend,
    required this.isDark,
  });

  final MonthPoint bucket;
  final bool isCurrent;
  final double maxSpend;
  final bool isDark;

  static const _monthAbbrev = [
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

  @override
  Widget build(BuildContext context) {
    final heightFactor = (bucket.spend / maxSpend).clamp(0.06, 1.0);
    final activeColor =
        isDark ? AppColorTokens.violetPrimary : AppColorTokens.ink;
    final inactiveColor = isDark
        ? AppColorTokens.bloomDarkTextTertiary.withValues(alpha: 0.3)
        : AppColorTokens.bloomChip;

    final monthLabel = _monthAbbrev[bucket.month.month - 1];

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          bucket.spend > 0 ? formatInrCompact(bucket.spend) : '',
          style: AppTheme.bloomMono(
            9,
            FontWeight.w500,
            color: isDark
                ? AppColorTokens.bloomDarkTextTertiary
                : AppColorTokens.inkTertiary,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 24,
          height: 80 * heightFactor,
          decoration: BoxDecoration(
            color: isCurrent ? activeColor : inactiveColor,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          monthLabel,
          style: AppTheme.bloomDisplay(
            11,
            isCurrent ? FontWeight.w700 : FontWeight.w500,
            color: isCurrent
                ? (isDark
                    ? AppColorTokens.bloomDarkTextPrimary
                    : AppColorTokens.ink)
                : (isDark
                    ? AppColorTokens.bloomDarkTextTertiary
                    : AppColorTokens.inkTertiary),
          ),
        ),
      ],
    );
  }
}

class _MoMComparisonCard extends ConsumerWidget {
  const _MoMComparisonCard({
    required this.mom,
    required this.currentSpend,
    required this.period,
    required this.isDark,
  });

  final MonthOverMonthSpend mom;
  final double currentSpend;
  final DashboardPeriod period;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final partialMonth = period.isPartialMonthAt(now);
    final comparisonLabel = period.comparisonLabelAt(now);
    final bg = isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard;
    final pctChange = mom.pctChange ?? 0.0;
    final isIncrease = pctChange > 0;
    final isZero = pctChange == 0;

    final badgeBg = isZero
        ? (isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomChip)
        : isIncrease
            ? (isDark
                ? AppColorTokens.bloomGold.withValues(alpha: 0.18)
                : const Color(0xFFFFF0D6))
            : (isDark
                ? AppColorTokens.bloomEmerald.withValues(alpha: 0.18)
                : const Color(0xFFD3F2E4));

    final badgeColor = isZero
        ? (isDark
            ? AppColorTokens.bloomDarkTextSecondary
            : AppColorTokens.inkSecondary)
        : isIncrease
            ? AppColorTokens.bloomGold
            : AppColorTokens.bloomEmerald;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.bloomCard),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MONTH OVER MONTH',
                  style: AppTheme.bloomDisplay(
                    11,
                    FontWeight.w600,
                    letterSpacing: 0.1,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextTertiary
                        : AppColorTokens.inkTertiary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  formatInr(currentSpend),
                  style: AppTheme.bloomMono(
                    26,
                    FontWeight.w600,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextPrimary
                        : AppColorTokens.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatInr(currentSpend)} spent${partialMonth ? ' so far' : ''} $comparisonLabel ${formatInr(mom.previous)}',
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  isIncrease
                      ? Icons.arrow_upward_rounded
                      : isZero
                          ? Icons.remove_rounded
                          : Icons.arrow_downward_rounded,
                  size: 14,
                  color: badgeColor,
                ),
                const SizedBox(width: 4),
                Text(
                  formatPercentChange(pctChange, decimals: 1),
                  style: AppTheme.bloomMono(
                    13,
                    FontWeight.w600,
                    color: badgeColor,
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

class _CategoryBreakdownSection extends StatelessWidget {
  const _CategoryBreakdownSection({
    required this.categories,
    required this.isDark,
  });

  final List<CategorySlice> categories;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SPENDING BY CATEGORY',
          style: AppTheme.bloomDisplay(
            11,
            FontWeight.w600,
            letterSpacing: 0.1,
            color: isDark
                ? AppColorTokens.bloomDarkTextTertiary
                : AppColorTokens.inkTertiary,
          ),
        ),
        const SizedBox(height: 12),
        if (categories.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadius.bloomCard),
            ),
            child: Center(
              child: Text(
                'No category data for this period',
                style: AppTheme.bloomDisplay(
                  13,
                  FontWeight.w400,
                  color: isDark
                      ? AppColorTokens.bloomDarkTextSecondary
                      : AppColorTokens.inkSecondary,
                ),
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadius.bloomCard),
            ),
            child: Column(
              children: [
                for (final cat in categories) ...[
                  Row(
                    children: [
                      BloomCategoryTile(
                        categoryId: cat.categoryId,
                        iconName: cat.icon,
                        size: 32,
                        borderRadius: 11,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  cat.name,
                                  style: AppTheme.bloomDisplay(
                                    13,
                                    FontWeight.w500,
                                    color: isDark
                                        ? AppColorTokens.bloomDarkTextPrimary
                                        : AppColorTokens.ink,
                                  ),
                                ),
                                Text(
                                  formatInr(cat.total),
                                  style: AppTheme.bloomMono(
                                    13,
                                    FontWeight.w500,
                                    color: isDark
                                        ? AppColorTokens.bloomDarkTextPrimary
                                        : AppColorTokens.ink,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: cat.share.clamp(0.0, 1.0),
                              backgroundColor: isDark
                                  ? AppColorTokens.bloomDarkOutline
                                  : AppColorTokens.bloomChip,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                CategoryVisuals.color(cat.categoryId),
                              ),
                              minHeight: 4,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (cat != categories.last) const SizedBox(height: 14),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _TopMerchantsSection extends StatelessWidget {
  const _TopMerchantsSection({
    required this.merchants,
    required this.isDark,
  });

  final List<MerchantStat> merchants;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TOP MERCHANTS',
          style: AppTheme.bloomDisplay(
            11,
            FontWeight.w600,
            letterSpacing: 0.1,
            color: isDark
                ? AppColorTokens.bloomDarkTextTertiary
                : AppColorTokens.inkTertiary,
          ),
        ),
        const SizedBox(height: 12),
        if (merchants.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadius.bloomCard),
            ),
            child: Center(
              child: Text(
                'No merchant data for this period',
                style: AppTheme.bloomDisplay(
                  13,
                  FontWeight.w400,
                  color: isDark
                      ? AppColorTokens.bloomDarkTextSecondary
                      : AppColorTokens.inkSecondary,
                ),
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadius.bloomCard),
            ),
            child: Column(
              children: [
                for (final merchant in merchants) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          merchant.name,
                          style: AppTheme.bloomDisplay(
                            13,
                            FontWeight.w500,
                            color: isDark
                                ? AppColorTokens.bloomDarkTextPrimary
                                : AppColorTokens.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        formatInr(merchant.total),
                        style: AppTheme.bloomMono(
                          13,
                          FontWeight.w500,
                          color: isDark
                              ? AppColorTokens.bloomDarkTextPrimary
                              : AppColorTokens.ink,
                        ),
                      ),
                    ],
                  ),
                  if (merchant != merchants.last) const SizedBox(height: 10),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

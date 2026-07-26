import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../../data/db/database.dart';
import '../../data/db/database_provider.dart';
import '../transactions/transactions_screen.dart';

/// Live recurring streams ordered by their next expected occurrence.
final recurringSeriesProvider = StreamProvider<List<RecurringSery>>((ref) {
  final databaseAsync = ref.watch(appDatabaseProvider);
  return databaseAsync.when(
    data: (database) => (database.select(database.recurringSeries)
          ..orderBy([
            (row) => OrderingTerm.asc(row.nextExpectedDate),
            (row) => OrderingTerm.asc(row.label),
          ]))
        .watch(),
    loading: () => const Stream<List<RecurringSery>>.empty(),
    error: (error, stackTrace) =>
        Stream<List<RecurringSery>>.error(error, stackTrace),
  );
});

/// Redesigned Bloom Recurring screen for subscriptions, bills, EMIs, and rent.
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final seriesAsync = ref.watch(recurringSeriesProvider);
    final items = seriesAsync.valueOrNull ?? const [];

    final activeItems = items.where((i) => i.status != 'inactive').toList();
    final totalCommitted = activeItems.fold<double>(
      0.0,
      (sum, item) => sum + (item.kind != 'income' ? item.expectedAmount : 0.0),
    );

    return Scaffold(
      backgroundColor:
          isDark ? AppColorTokens.bloomDarkBase : AppColorTokens.bloomBase,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Recurring',
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
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            // Monthly Commitments Card
            _CommitmentsSummaryCard(
              totalCommitted: totalCommitted,
              activeCount: activeItems.length,
              isDark: isDark,
            ),
            const SizedBox(height: 24),

            Text(
              'Active Subscriptions & EMIs',
              style: AppTheme.bloomDisplay(
                16,
                FontWeight.w600,
                color: isDark
                    ? AppColorTokens.bloomDarkTextPrimary
                    : AppColorTokens.ink,
              ),
            ),
            const SizedBox(height: 12),

            if (items.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColorTokens.bloomDarkCard
                      : AppColorTokens.bloomCard,
                  borderRadius: BorderRadius.circular(AppRadius.bloomCard),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.event_repeat_rounded,
                      size: 44,
                      color: isDark
                          ? AppColorTokens.bloomDarkTextTertiary
                          : AppColorTokens.inkTertiary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No recurring payments detected yet',
                      style: AppTheme.bloomDisplay(
                        14,
                        FontWeight.w600,
                        color: isDark
                            ? AppColorTokens.bloomDarkTextPrimary
                            : AppColorTokens.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'PaisaTrack identifies subscriptions, EMIs, bills, and rent after matching transactions arrive.',
                      style: AppTheme.bloomDisplay(
                        12,
                        FontWeight.w400,
                        color: isDark
                            ? AppColorTokens.bloomDarkTextSecondary
                            : AppColorTokens.inkSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              for (final series in items) ...[
                _RecurringTileRow(
                  series: series,
                  isDark: isDark,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TransactionsScreen(
                          initialMerchant: series.label,
                        ),
                      ),
                    );
                  },
                ),
                if (series != items.last) const SizedBox(height: 10),
              ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _CommitmentsSummaryCard extends StatelessWidget {
  const _CommitmentsSummaryCard({
    required this.totalCommitted,
    required this.activeCount,
    required this.isDark,
  });

  final double totalCommitted;
  final int activeCount;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark
        ? AppColorTokens.bloomGold.withValues(alpha: 0.14)
        : const Color(0xFFFFF3D8);
    final border = isDark
        ? AppColorTokens.bloomGold.withValues(alpha: 0.3)
        : const Color(0xFFF3D9A0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.bloomCard),
        border: Border.all(color: border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'MONTHLY COMMITMENTS',
                  style: AppTheme.bloomDisplay(
                    11,
                    FontWeight.w600,
                    letterSpacing: 0.12,
                    color: isDark
                        ? const Color(0xFFF3DFB4)
                        : const Color(0xFF8A5A00),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColorTokens.ink.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$activeCount active',
                  style: AppTheme.bloomMono(
                    11,
                    FontWeight.w600,
                    color: isDark
                        ? const Color(0xFFF3DFB4)
                        : const Color(0xFF8A5A00),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${formatInr(totalCommitted)}/mo',
            style: AppTheme.bloomMono(
              32,
              FontWeight.w600,
              letterSpacing: -0.04,
              color: isDark ? Colors.white : AppColorTokens.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Committed to rent, EMIs, and monthly subscriptions.',
            style: AppTheme.bloomDisplay(
              12,
              FontWeight.w400,
              color: isDark
                  ? AppColorTokens.bloomDarkTextSecondary
                  : const Color(0xFF7E6A45),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecurringTileRow extends StatelessWidget {
  const _RecurringTileRow({
    required this.series,
    required this.isDark,
    required this.onTap,
  });

  final RecurringSery series;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard;

    final isIncome = series.kind == 'income';
    final formattedDate = _formatDate(series.nextExpectedDate);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.bloomRow),
        ),
        child: Row(
          children: [
            BloomCategoryTile(
              categoryId: series.kind,
              size: 36,
              borderRadius: 13,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          series.label,
                          style: AppTheme.bloomDisplay(
                            14,
                            FontWeight.w500,
                            color: isDark
                                ? AppColorTokens.bloomDarkTextPrimary
                                : AppColorTokens.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColorTokens.bloomEmerald
                                  .withValues(alpha: 0.18)
                              : const Color(0xFFD3F2E4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Active',
                          style: AppTheme.bloomDisplay(
                            10,
                            FontWeight.w600,
                            color: isDark
                                ? AppColorTokens.bloomCreditDark
                                : const Color(0xFF0E9F6E),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${series.period.toUpperCase()} · Next due $formattedDate',
                    style: AppTheme.bloomDisplay(
                      11,
                      FontWeight.w400,
                      color: isDark
                          ? AppColorTokens.bloomDarkTextTertiary
                          : AppColorTokens.inkTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            BloomAmount(
              amount: isIncome ? series.expectedAmount : -series.expectedAmount,
              size: 15,
              weight: FontWeight.w500,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${_shortMonth(local.month)} ${local.day}';
  }

  String _shortMonth(int month) => const [
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
      ][month - 1];
}

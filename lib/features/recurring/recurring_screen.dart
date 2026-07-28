import 'package:drift/drift.dart' show OrderingTerm, Value, leftOuterJoin;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../../data/db/database.dart';
import '../../data/db/database_provider.dart';
import '../transactions/transactions_screen.dart';

class RecurringSeriesItem {
  const RecurringSeriesItem({
    required this.series,
    this.categoryHint,
  });

  final RecurringSery series;
  final String? categoryHint;

  String get categoryId {
    final hint = categoryHint?.trim();
    if (hint != null && hint.isNotEmpty) {
      return hint;
    }
    return switch (series.kind.toLowerCase()) {
      'subscription' => 'subscriptions',
      'emi' => 'emi_loans',
      'income' => 'income',
      'rent' => 'rent_housing',
      'bill' => 'bills_utilities',
      _ => series.kind,
    };
  }
}

/// Live recurring streams ordered by their next expected occurrence.
final recurringSeriesProvider =
    StreamProvider<List<RecurringSeriesItem>>((ref) {
  final databaseAsync = ref.watch(appDatabaseProvider);
  return databaseAsync.when(
    data: (database) {
      final query = database.select(database.recurringSeries).join([
        leftOuterJoin(
          database.merchants,
          database.merchants.id.equalsExp(database.recurringSeries.merchantId),
        ),
      ])
        ..orderBy([
          OrderingTerm.asc(database.recurringSeries.nextExpectedDate),
          OrderingTerm.asc(database.recurringSeries.label),
        ]);

      return query.watch().map((rows) {
        return rows.map((row) {
          final series = row.readTable(database.recurringSeries);
          final merchant = row.readTableOrNull(database.merchants);
          return RecurringSeriesItem(
            series: series,
            categoryHint: merchant?.categoryHint,
          );
        }).toList();
      });
    },
    loading: () => const Stream<List<RecurringSeriesItem>>.empty(),
    error: (error, stackTrace) =>
        Stream<List<RecurringSeriesItem>>.error(error, stackTrace),
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

    final activeItems = items
        .where((i) => i.series.status != 'inactive' && i.series.status != 'cancelled')
        .toList();
    final totalCommitted = activeItems.fold<double>(
      0.0,
      (sum, item) => sum + (item.series.kind != 'income' ? item.series.expectedAmount : 0.0),
    );

    final now = DateTime.now();
    final fourteenDaysOut = now.add(const Duration(days: 14));

    final upcoming14d = items.where((i) {
      final date = i.series.nextExpectedDate.toLocal();
      return i.series.status != 'inactive' &&
          i.series.status != 'cancelled' &&
          !date.isAfter(fourteenDaysOut);
    }).toList();

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

            // 14-Day Timeline Section (if any upcoming)
            if (upcoming14d.isNotEmpty) ...[
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 18,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextSecondary
                        : AppColorTokens.inkSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Next 14 Days Timeline',
                    style: AppTheme.bloomDisplay(
                      15,
                      FontWeight.w600,
                      color: isDark
                          ? AppColorTokens.bloomDarkTextPrimary
                          : AppColorTokens.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final item in upcoming14d) ...[
                _RecurringTileRow(
                  item: item,
                  isDark: isDark,
                  onTap: () => _showSeriesOptions(context, ref, item.series),
                ),
                if (item != upcoming14d.last) const SizedBox(height: 8),
              ],
              const SizedBox(height: 24),
            ],

            Text(
              'All Recurring Subscriptions & EMIs',
              style: AppTheme.bloomDisplay(
                15,
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
              for (final item in items) ...[
                _RecurringTileRow(
                  item: item,
                  isDark: isDark,
                  onTap: () => _showSeriesOptions(context, ref, item.series),
                ),
                if (item != items.last) const SizedBox(height: 10),
              ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  void _showSeriesOptions(
    BuildContext context,
    WidgetRef ref,
    RecurringSery series,
  ) {
    showBloomModalSheet(
      context: context,
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                series.label,
                style: AppTheme.bloomDisplay(
                  18,
                  FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${series.period.toUpperCase()} · ${formatInr(series.expectedAmount)}',
                style: AppTheme.bloomDisplay(
                  13,
                  FontWeight.w400,
                  color: AppColorTokens.inkSecondary,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.list_alt_rounded),
                title: const Text('View transactions'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TransactionsScreen(
                        initialMerchant: series.label,
                      ),
                    ),
                  );
                },
              ),
              if (series.status != 'cancelled')
                ListTile(
                  leading: const Icon(Icons.cancel_outlined, color: Colors.red),
                  title: const Text('Mark as Cancelled'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    final db = await ref.read(appDatabaseProvider.future);
                    await (db.update(db.recurringSeries)
                          ..where((row) => row.id.equals(series.id)))
                        .write(
                      const RecurringSeriesCompanion(
                        status: Value('cancelled'),
                      ),
                    );
                  },
                )
              else
                ListTile(
                  leading: const Icon(
                    Icons.check_circle_outline,
                    color: AppColorTokens.bloomEmerald,
                  ),
                  title: const Text('Reactivate Series'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    final db = await ref.read(appDatabaseProvider.future);
                    await (db.update(db.recurringSeries)
                          ..where((row) => row.id.equals(series.id)))
                        .write(
                      const RecurringSeriesCompanion(
                        status: Value('active'),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
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
    required this.item,
    required this.isDark,
    required this.onTap,
  });

  final RecurringSeriesItem item;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final series = item.series;
    final bg = isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard;
    final isIncome = series.kind == 'income';
    final formattedDate = _formatDate(series.nextExpectedDate);

    final statusSpec = _statusSpec(series.status, isDark);

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
              categoryId: item.categoryId,
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
                      const SizedBox(width: 4),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusSpec.bg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            statusSpec.label,
                            style: AppTheme.bloomDisplay(
                              10,
                              FontWeight.w600,
                              color: statusSpec.textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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

  _StatusSpec _statusSpec(String status, bool isDark) {
    switch (status) {
      case 'expected':
        return _StatusSpec(
          label: 'Expected',
          bg: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          textColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
        );
      case 'missed':
        return _StatusSpec(
          label: 'Missed',
          bg: isDark ? const Color(0xFF451A03) : const Color(0xFFFFEDD5),
          textColor: isDark ? const Color(0xFFF97316) : const Color(0xFFC2410C),
        );
      case 'price_changed':
        return _StatusSpec(
          label: 'Price Changed',
          bg: isDark
              ? AppColorTokens.bloomGold.withValues(alpha: 0.18)
              : const Color(0xFFFFF0D6),
          textColor:
              isDark ? AppColorTokens.bloomGold : const Color(0xFF8A5A00),
        );
      case 'settled':
        return _StatusSpec(
          label: 'Settled',
          bg: isDark ? const Color(0xFF14532D) : const Color(0xFFDCFCE7),
          textColor: isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
        );
      case 'inactive':
        return _StatusSpec(
          label: 'Inactive',
          bg: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF1F5F9),
          textColor: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
        );
      case 'cancelled':
        return _StatusSpec(
          label: 'Cancelled',
          bg: isDark ? const Color(0xFF3B0764) : const Color(0xFFF3E8FF),
          textColor: isDark ? const Color(0xFFC084FC) : const Color(0xFF7E22CE),
        );
      case 'active':
      default:
        return _StatusSpec(
          label: 'Active',
          bg: isDark
              ? AppColorTokens.bloomEmerald.withValues(alpha: 0.18)
              : const Color(0xFFD3F2E4),
          textColor:
              isDark ? AppColorTokens.bloomCreditDark : const Color(0xFF0E9F6E),
        );
    }
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

class _StatusSpec {
  const _StatusSpec({
    required this.label,
    required this.bg,
    required this.textColor,
  });

  final String label;
  final Color bg;
  final Color textColor;
}

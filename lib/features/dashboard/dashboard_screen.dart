import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../capture/permissions/sms_permission.dart';
import '../../capture/permissions/sms_permission_provider.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/paisa_colors.dart';
import '../../core/widgets/app_state_views.dart';
import '../assistant/assistant_screen.dart';
import '../review/weekly_review_screen.dart';
import '../recurring/recurring_screen.dart';
import '../settings/settings_screen.dart';
import '../transactions/transaction_detail_screen.dart';
import '../transactions/transactions_screen.dart';
import 'dashboard_providers.dart';
import 'dashboard_widgets.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final totals = ref.watch(monthDirectionTotalsProvider);
    final net = ref.watch(monthNetProvider);
    final dailyAvg = ref.watch(dailyAverageSpendProvider);
    final projected = ref.watch(projectedMonthEndSpendProvider);
    final mom = ref.watch(monthOverMonthSpendProvider);
    final categories = ref.watch(categoryBreakdownProvider);
    final merchants = ref.watch(topMerchantsProvider);
    final trend = ref.watch(sixMonthTrendProvider);
    final reviewAttention = ref.watch(reviewAttentionProvider);
    final recent = ref.watch(recentTransactionsProvider);
    final upcoming = ref.watch(upcomingRecurringProvider);
    final period = ref.watch(dashboardPeriodProvider);

    final hasActivity = totals.debitTotal > 0 || totals.creditTotal > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
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
      body: ListView(
        padding: AppSpacing.screen,
        children: [
          const _SmsPermissionBanner(),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _selectPeriod(context, ref, period),
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(
                period.label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            period.isCalendarMonth
                ? 'Monthly overview'
                : 'Selected period overview',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (hasActivity) ...[
            HeroFinancialCard(
              net: net,
              spent: totals.debitTotal,
              received: totals.creditTotal,
              monthComparison: mom,
              comparisonPeriodLabel: period.isCalendarMonth
                  ? 'the previous month'
                  : 'the previous period',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TransactionsScreen(),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            CompactMetricRow(
              dailyAverage: dailyAvg,
              monthComparison: mom,
              projectedSpend: projected,
              comparisonLabel: period.comparisonLabel,
            ),
          ] else
            EmptyStateView(
              illustration: AppIllustrations.wallet,
              title: 'No transactions in ${period.label}',
              message:
                  'Transactions read from SMS or added manually will build your overview here.',
              actionLabel: 'Add transaction',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TransactionsScreen(),
                ),
              ),
            ),
          if (reviewAttention != null) ...[
            const SizedBox(height: AppSpacing.md),
            ReviewAttentionCard(
              attention: reviewAttention,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const WeeklyReviewScreen(),
                ),
              ),
            ),
          ],
          if (categories.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            CategoryBreakdownCard(
              slices: categories,
              onSliceTap: (slice) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TransactionsScreen(
                    initialCategoryId: slice.categoryId,
                    initialCategoryName: slice.name,
                  ),
                ),
              ),
            ),
          ],
          if (merchants.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            TopMerchantsCard(
              merchants: merchants,
              onMerchantTap: (merchant) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TransactionsScreen(
                    initialMerchant: merchant.name,
                  ),
                ),
              ),
            ),
          ],
          if (recent.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            RecentTransactionsCard(
              transactions: recent,
              onTransactionTap: (id) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TransactionDetailScreen(txnId: id),
                ),
              ),
            ),
          ],
          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            UpcomingRecurringCard(
              series: upcoming,
              onViewAll: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RecurringScreen(),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          TrendSparkline(points: trend),
        ],
      ),
    );
  }
}

enum _DashboardPeriodChoice {
  currentMonth,
  previousMonth,
  today,
  last7Days,
  last30Days,
  chooseMonth,
  customRange,
}

Future<void> _selectPeriod(
  BuildContext context,
  WidgetRef ref,
  DashboardPeriod current,
) async {
  final choice = await showModalBottomSheet<_DashboardPeriodChoice>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.calendar_view_month_outlined),
            title: const Text('Current month'),
            onTap: () => Navigator.pop(
              context,
              _DashboardPeriodChoice.currentMonth,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.history_outlined),
            title: const Text('Previous month'),
            onTap: () => Navigator.pop(
              context,
              _DashboardPeriodChoice.previousMonth,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.today_outlined),
            title: const Text('Today'),
            onTap: () => Navigator.pop(context, _DashboardPeriodChoice.today),
          ),
          ListTile(
            leading: const Icon(Icons.date_range_outlined),
            title: const Text('Last 7 days'),
            onTap: () =>
                Navigator.pop(context, _DashboardPeriodChoice.last7Days),
          ),
          ListTile(
            leading: const Icon(Icons.date_range_outlined),
            title: const Text('Last 30 days'),
            onTap: () =>
                Navigator.pop(context, _DashboardPeriodChoice.last30Days),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('Choose month'),
            onTap: () =>
                Navigator.pop(context, _DashboardPeriodChoice.chooseMonth),
          ),
          ListTile(
            leading: const Icon(Icons.edit_calendar_outlined),
            title: const Text('Custom date range'),
            onTap: () =>
                Navigator.pop(context, _DashboardPeriodChoice.customRange),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  final now = DateTime.now();
  DashboardPeriod? selected;
  switch (choice) {
    case _DashboardPeriodChoice.currentMonth:
      selected = DashboardPeriod.month(now);
    case _DashboardPeriodChoice.previousMonth:
      selected = DashboardPeriod.month(DateTime(now.year, now.month - 1));
    case _DashboardPeriodChoice.today:
      selected = DashboardPeriod.lastDays(1, now: now);
    case _DashboardPeriodChoice.last7Days:
      selected = DashboardPeriod.lastDays(7, now: now);
    case _DashboardPeriodChoice.last30Days:
      selected = DashboardPeriod.lastDays(30, now: now);
    case _DashboardPeriodChoice.chooseMonth:
      final month = await showDialog<DateTime>(
        context: context,
        builder: (context) => _MonthPickerDialog(
          initialMonth: current.start,
          lastMonth: now,
        ),
      );
      if (month != null) selected = DashboardPeriod.month(month);
    case _DashboardPeriodChoice.customRange:
      final initialEnd = current.end
          .subtract(const Duration(days: 1))
          .clampDate(DateTime(2000), now);
      final initialStart = current.start.clampDate(DateTime(2000), initialEnd);
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: now,
        initialDateRange: DateTimeRange(
          start: initialStart,
          end: initialEnd,
        ),
        helpText: 'Choose dashboard date range',
      );
      if (range != null) {
        selected = DashboardPeriod.range(range.start, range.end);
      }
  }

  if (selected != null) {
    ref.read(dashboardPeriodProvider.notifier).state = selected;
  }
}

class _MonthPickerDialog extends StatefulWidget {
  const _MonthPickerDialog({
    required this.initialMonth,
    required this.lastMonth,
  });

  final DateTime initialMonth;
  final DateTime lastMonth;

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _year = widget.initialMonth.year;

  static const _months = [
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
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      title: Row(
        children: [
          IconButton(
            tooltip: 'Previous year',
            onPressed: _year > 2000 ? () => setState(() => _year--) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              '$_year',
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            tooltip: 'Next year',
            onPressed: _year < widget.lastMonth.year
                ? () => setState(() => _year++)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: GridView.builder(
          shrinkWrap: true,
          itemCount: 12,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 1.8,
            crossAxisSpacing: AppSpacing.sm,
            mainAxisSpacing: AppSpacing.sm,
          ),
          itemBuilder: (context, index) {
            final month = DateTime(_year, index + 1);
            final isFuture = month.isAfter(
              DateTime(widget.lastMonth.year, widget.lastMonth.month),
            );
            final isSelected = currentMonth(widget.initialMonth) == month;
            return FilledButton.tonal(
              onPressed: isFuture ? null : () => Navigator.pop(context, month),
              style: FilledButton.styleFrom(
                backgroundColor: isSelected
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : null,
              ),
              child: Text(_months[index]),
            );
          },
        ),
      ),
    );
  }

  static DateTime currentMonth(DateTime value) =>
      DateTime(value.year, value.month);
}

extension on DateTime {
  DateTime clampDate(DateTime minimum, DateTime maximum) {
    if (isBefore(minimum)) return minimum;
    if (isAfter(maximum)) return maximum;
    return this;
  }
}

/// Persistent reminder shown while SMS access is not granted, so a user who
/// entered the app without permission can turn on automatic capture later
/// (docs/design-system.md §9: warning tint, not error). Renders nothing once
/// permission is granted.
class _SmsPermissionBanner extends ConsumerWidget {
  const _SmsPermissionBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permission = ref.watch(smsPermissionControllerProvider).valueOrNull;
    if (permission == null || permission.isGranted) {
      return const SizedBox.shrink();
    }

    final paisa = PaisaColors.of(context);
    final permanentlyDenied =
        permission == SmsPermissionStatus.permanentlyDenied;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: paisa.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.sms_failed_outlined, size: 20, color: paisa.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  permanentlyDenied
                      ? 'Automatic SMS capture is off. Enable SMS access in '
                          'system settings to turn it on. You can still add '
                          'transactions manually.'
                      : 'Automatic SMS capture is off. Grant SMS access to '
                          'capture bank and UPI messages automatically.',
                ),
                if (!permanentlyDenied) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: ref
                          .read(smsPermissionControllerProvider.notifier)
                          .request,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Grant SMS access'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/bloom/bloom_sheet_scaffold.dart';
import 'dashboard_providers.dart';

/// Modal sheet for choosing dashboard timeframe / period.
class BloomDatePeriodSheet extends ConsumerWidget {
  const BloomDatePeriodSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentPeriod = ref.watch(dashboardPeriodProvider);
    final now = DateTime.now();

    final options = <_PeriodOption>[
      _PeriodOption(
        label: 'Current month (${_monthName(now.month)} ${now.year})',
        period: DashboardPeriod.month(now),
      ),
      _PeriodOption(
        label:
            'Previous month (${_monthName(now.month - 1 <= 0 ? 12 : now.month - 1)} ${now.month - 1 <= 0 ? now.year - 1 : now.year})',
        period: DashboardPeriod.month(DateTime(now.year, now.month - 1)),
      ),
      _PeriodOption(
        label: 'Last 7 days',
        period: DashboardPeriod.lastDays(7, now: now),
      ),
      _PeriodOption(
        label: 'Last 30 days',
        period: DashboardPeriod.lastDays(30, now: now),
      ),
    ];

    return BloomSheetScaffold(
      title: 'Select Period',
      showBack: false,
      showClose: true,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final opt in options)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    opt.label,
                    style: AppTheme.bloomDisplay(
                      15,
                      FontWeight.w500,
                      color: isDark
                          ? AppColorTokens.bloomDarkTextPrimary
                          : AppColorTokens.ink,
                    ),
                  ),
                  trailing: opt.period.label == currentPeriod.label
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: AppColorTokens.violetPrimary,
                        )
                      : null,
                  onTap: () {
                    ref.read(dashboardPeriodProvider.notifier).state =
                        opt.period;
                    Navigator.of(context).pop();
                  },
                ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.date_range_rounded),
                title: Text(
                  'Custom date range...',
                  style: AppTheme.bloomDisplay(
                    15,
                    FontWeight.w500,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextPrimary
                        : AppColorTokens.ink,
                  ),
                ),
                onTap: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    initialDateRange: DateTimeRange(
                      start: currentPeriod.start,
                      end: currentPeriod.end.subtract(const Duration(days: 1)),
                    ),
                  );
                  if (picked != null) {
                    ref.read(dashboardPeriodProvider.notifier).state =
                        DashboardPeriod.range(picked.start, picked.end);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final m = ((month - 1) % 12 + 12) % 12;
    return months[m];
  }
}

class _PeriodOption {
  const _PeriodOption({required this.label, required this.period});
  final String label;
  final DashboardPeriod period;
}

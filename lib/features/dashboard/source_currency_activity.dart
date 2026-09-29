import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/source_currency.dart';
import 'dashboard_providers.dart';

/// Keeps non-INR activity visible without mixing nominal amounts into rupee
/// budget totals. Legacy rows with no currency evidence appear as unknown.
class BloomSourceCurrencyActivity extends ConsumerWidget {
  const BloomSourceCurrencyActivity({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(dashboardAggregateProvider).valueOrNull;
    if (snapshot == null) return const SizedBox.shrink();
    final currencies = snapshot.currencyTotals
        .where((item) => item.currencyCode != 'INR')
        .toList(growable: false);
    if (currencies.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppColorTokens.bloomDarkTextSecondary
        : AppColorTokens.inkSecondary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard,
        borderRadius: BorderRadius.circular(AppRadius.bloomCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OTHER SOURCE CURRENCIES · THIS PERIOD',
            style: AppTheme.bloomDisplay(
              11,
              FontWeight.w600,
              letterSpacing: 0.12,
              color: secondary,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in currencies) ...[
            if (item.debitTotal > 0)
              _CurrencyActivityRow(
                label: SourceCurrency(
                  code: item.currencyCode,
                  symbol: item.currencySymbol,
                ).label,
                direction: 'Spent',
                amount: item.debitTotal,
                currencyCode: item.currencyCode,
                currencySymbol: item.currencySymbol,
                isDark: isDark,
              ),
            if (item.creditTotal > 0)
              _CurrencyActivityRow(
                label: SourceCurrency(
                  code: item.currencyCode,
                  symbol: item.currencySymbol,
                ).label,
                direction: 'Received',
                amount: item.creditTotal,
                currencyCode: item.currencyCode,
                currencySymbol: item.currencySymbol,
                isDark: isDark,
              ),
          ],
          const SizedBox(height: 4),
          Text(
            'Kept separate from INR budgets and totals; no exchange rate is applied.',
            style: AppTheme.bloomDisplay(11, FontWeight.w400, color: secondary),
          ),
        ],
      ),
    );
  }
}

class _CurrencyActivityRow extends StatelessWidget {
  const _CurrencyActivityRow({
    required this.label,
    required this.direction,
    required this.amount,
    required this.currencyCode,
    required this.currencySymbol,
    required this.isDark,
  });

  final String label;
  final String direction;
  final double amount;
  final String? currencyCode;
  final String? currencySymbol;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$label · $direction',
                style: AppTheme.bloomDisplay(
                  12,
                  FontWeight.w400,
                  color: isDark
                      ? AppColorTokens.bloomDarkTextSecondary
                      : AppColorTokens.inkSecondary,
                ),
              ),
            ),
            Flexible(
              child: Text(
                formatSourceAmount(
                  amount,
                  currencyCode: currencyCode,
                  currencySymbol: currencySymbol,
                ),
                style: AppTheme.bloomMono(
                  12,
                  FontWeight.w500,
                  color: isDark ? Colors.white : AppColorTokens.ink,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      );
}

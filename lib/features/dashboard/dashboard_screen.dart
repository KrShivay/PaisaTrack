import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../settings/app_settings.dart';
import '../settings/settings_screen.dart';
import '../transactions/transaction_detail_screen.dart';
import 'dashboard_widgets.dart';

/// Post-onboarding Bloom Dashboard screen.
///
/// Answers "can I spend today?" in under a second with the 230px Hero Ring,
/// metric switcher pills, dark emerald budget card, top categories section,
/// insight card, and recent transaction list.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(appSettingsControllerProvider).valueOrNull;
    final streak = settings?.streak ?? 6;

    return Scaffold(
      backgroundColor:
          isDark ? AppColorTokens.bloomDarkBase : AppColorTokens.bloomBase,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            // Header Row: Mascot (36px) + Greeting + Streak chip
            Row(
              children: [
                const BloomMascot(
                  size: 36,
                  bob: true,
                  pulseRing: false,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hey Shivay',
                        style: AppTheme.bloomDisplay(
                          15,
                          FontWeight.w600,
                          color: isDark
                              ? AppColorTokens.bloomDarkTextPrimary
                              : AppColorTokens.ink,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Lighter week than usual',
                        style: AppTheme.bloomDisplay(
                          11,
                          FontWeight.w400,
                          color: isDark
                              ? AppColorTokens.bloomDarkTextTertiary
                              : AppColorTokens.inkTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Streak Chip / Settings icon
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen(),
                      ),
                    );
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColorTokens.bloomGold.withValues(alpha: 0.16)
                          : const Color(0xFFFFF0D6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.local_fire_department_rounded,
                          size: 14,
                          color: AppColorTokens.bloomGold,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$streak day streak',
                          style: AppTheme.bloomDisplay(
                            12,
                            FontWeight.w600,
                            color: isDark
                                ? AppColorTokens.bloomGold
                                : const Color(0xFF8A5A00),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Hero Ring (230px)
            const BloomHeroRing(),
            const SizedBox(height: 16),

            // Metric Switcher Pills (Safe today, Net flow, Burn, Runway)
            const BloomMetricSwitcherPills(),
            const SizedBox(height: 24),

            // Budget Card
            const BloomBudgetCard(),
            const SizedBox(height: 24),

            // Where it went (Top 3 categories)
            BloomTopCategoriesSection(
              onViewAll: () {
                // Navigate to Activity tab via default notification or pop
              },
            ),
            const SizedBox(height: 24),

            // Insight Card (Blinkit cap)
            const BloomInsightCard(),
            const SizedBox(height: 24),

            // Today / Recent Transactions
            BloomTodayList(
              onTransactionTap: (txn) {
                showBloomModalSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => TransactionDetailScreen(txnId: txn.id),
                );
              },
            ),

            // Bottom clearance for floating nav pill
            const SizedBox(height: 110),
          ],
        ),
      ),
    );
  }
}

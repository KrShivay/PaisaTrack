import 'dart:math' as math;
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../../core/widgets/category_picker_sheet.dart';
import '../../core/undo/undo_controller.dart';
import '../../data/db/database.dart' show Category;
import '../../data/db/database_provider.dart';
import '../../data/models/normalized_transaction_record.dart';
import '../../data/repositories/transaction_repository.dart';
import '../settings/app_settings.dart';
import '../transactions/transactions_providers.dart';

/// Redesigned Bloom Sort screen: Tinder-style card swipe review with Inbox Zero state.
class WeeklyReviewScreen extends ConsumerStatefulWidget {
  const WeeklyReviewScreen({super.key});

  @override
  ConsumerState<WeeklyReviewScreen> createState() => _WeeklyReviewScreenState();
}

class _WeeklyReviewScreenState extends ConsumerState<WeeklyReviewScreen> {
  double _dragDx = 0.0;
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final queueAsync = ref.watch(reviewQueueProvider);
    final items = queueAsync.valueOrNull ?? const [];

    if (items.isEmpty || _currentIndex >= items.length) {
      return _InboxZeroView(isDark: isDark);
    }

    final item = items[_currentIndex];
    final remainingCount = items.length - _currentIndex;
    final totalCount = items.length;

    return Scaffold(
      backgroundColor:
          isDark ? AppColorTokens.bloomDarkBase : AppColorTokens.bloomBase,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              // Header Row: Title + counter
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sort',
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
                        '$remainingCount left to sort today',
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
                  Container(
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
                    child: Text(
                      '${_currentIndex + 1} of $totalCount',
                      style: AppTheme.bloomMono(
                        12,
                        FontWeight.w500,
                        color: isDark
                            ? AppColorTokens.bloomDarkTextSecondary
                            : AppColorTokens.inkSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Swipeable Card Container
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setState(() => _dragDx += details.delta.dx);
                    },
                    onPanEnd: (details) {
                      if (_dragDx > 100) {
                        _confirmItem(item);
                      } else if (_dragDx < -100) {
                        _recategorizeItem(item);
                      }
                      setState(() => _dragDx = 0.0);
                    },
                    child: Transform.translate(
                      offset: Offset(_dragDx, 0),
                      child: Transform.rotate(
                        angle: (_dragDx / 300) * (math.pi / 12),
                        child: _SortCard(
                          item: item,
                          dragDx: _dragDx,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Action Buttons Row (Change category / Keep)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Change category button (Gold)
                  GestureDetector(
                    onTap: () => _recategorizeItem(item),
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark
                            ? AppColorTokens.bloomGold.withValues(alpha: 0.18)
                            : const Color(0xFFFFF0D6),
                        boxShadow: AppColorTokens.bloomSortCardShadow,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.sell_outlined,
                          size: 24,
                          color: AppColorTokens.bloomGold,
                        ),
                      ),
                    ),
                  ),
                  // Keep button (Emerald)
                  GestureDetector(
                    onTap: () => _confirmItem(item),
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark
                            ? AppColorTokens.bloomEmerald
                                .withValues(alpha: 0.18)
                            : const Color(0xFFD3F2E4),
                        boxShadow: AppColorTokens.bloomSortCardShadow,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.check_rounded,
                          size: 26,
                          color: AppColorTokens.bloomEmerald,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 110),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmItem(TransactionReviewItem item) async {
    setState(() => _currentIndex++);
    final database = await ref.read(appDatabaseProvider.future);
    final repo = ref.read(transactionRepositoryProvider(database));
    await repo.updateWithFeedback(
      txnId: item.id,
      status: const Value('confirmed'),
      context: 'sort_confirm',
    );

    ref.read(undoControllerProvider.notifier).pushUndo(
          UndoToken(
            id: 'sort_confirm_${item.id}',
            message: 'Marked confirmed',
            undoAction: () async {
              await repo.updateWithFeedback(
                txnId: item.id,
                status: const Value('needs_review'),
                context: 'undo_sort',
              );
              if (mounted) setState(() => _currentIndex--);
            },
          ),
        );
  }

  Future<void> _recategorizeItem(TransactionReviewItem item) async {
    final categories = await ref.read(categoryListProvider.future);
    if (!mounted) return;
    final chosen = await showBloomModalSheet<Category>(
      context: context,
      isScrollControlled: true,
      builder: (context) => CategoryPickerSheet(
        categories: categories,
        title: 'Change Category',
      ),
    );
    if (chosen == null || !mounted) return;

    setState(() => _currentIndex++);
    final database = await ref.read(appDatabaseProvider.future);
    final repo = ref.read(transactionRepositoryProvider(database));
    final prevCategory = item.categoryId;

    await repo.updateWithFeedback(
      txnId: item.id,
      categoryId: Value(chosen.id),
      context: 'sort_categorize',
    );

    ref.read(undoControllerProvider.notifier).pushUndo(
          UndoToken(
            id: 'sort_cat_${item.id}',
            message: 'Filed under ${chosen.name}',
            undoAction: () async {
              await repo.updateWithFeedback(
                txnId: item.id,
                categoryId: Value(prevCategory),
                context: 'undo_sort',
              );
              if (mounted) setState(() => _currentIndex--);
            },
          ),
        );
  }
}

class _SortCard extends StatelessWidget {
  const _SortCard({
    required this.item,
    required this.dragDx,
    required this.isDark,
  });

  final TransactionReviewItem item;
  final double dragDx;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard;
    final border = isDark
        ? Border.all(color: AppColorTokens.bloomDarkOutline, width: 1)
        : null;

    final isSwipingRight = dragDx > 40;
    final isSwipingLeft = dragDx < -40;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(26),
        border: border,
        boxShadow: AppColorTokens.bloomSortCardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Stamp Overlay
          if (isSwipingRight)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: AppColorTokens.bloomEmerald,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'KEEP',
                style: AppTheme.bloomDisplay(
                  14,
                  FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            )
          else if (isSwipingLeft)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: AppColorTokens.bloomGold,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'CHANGE CATEGORY',
                style: AppTheme.bloomDisplay(
                  14,
                  FontWeight.w700,
                  color: AppColorTokens.ink,
                ),
              ),
            )
          else
            const SizedBox(height: 28),

          const SizedBox(height: 12),
          // Category Tile 52px
          BloomCategoryTile(
            categoryId: item.categoryId,
            size: 52,
            borderRadius: 18,
          ),
          const SizedBox(height: 16),

          // Title
          Text(
            item.displayName,
            style: AppTheme.bloomDisplay(
              20,
              FontWeight.w600,
              color: isDark
                  ? AppColorTokens.bloomDarkTextPrimary
                  : AppColorTokens.ink,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),

          // Category name & merchant raw
          Text(
            '${item.categoryName ?? "Uncategorised"}${item.merchantRaw != null ? " · ${item.merchantRaw}" : ""}',
            style: AppTheme.bloomDisplay(
              13,
              FontWeight.w400,
              color: isDark
                  ? AppColorTokens.bloomDarkTextSecondary
                  : AppColorTokens.inkSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),

          // Date / time
          Text(
            _formatTime(item.ts),
            style: AppTheme.bloomMono(
              12,
              FontWeight.w400,
              color: isDark
                  ? AppColorTokens.bloomDarkTextTertiary
                  : AppColorTokens.inkTertiary,
            ),
          ),
          const SizedBox(height: 24),

          // Hero Amount 48px
          BloomAmount(
            amount: item.direction == TransactionDirection.debit
                ? -item.amount
                : item.amount,
            size: 48,
            weight: FontWeight.w600,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _formatTime(DateTime date) {
    final h =
        date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final m = date.minute.toString().padLeft(2, '0');
    final ampm = date.hour >= 12 ? 'pm' : 'am';
    return '$h:$m $ampm · ${_shortMonth(date.month)} ${date.day}';
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

class _InboxZeroView extends ConsumerWidget {
  const _InboxZeroView({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsControllerProvider).valueOrNull;
    final streak = settings?.streak ?? 6;

    return Scaffold(
      backgroundColor:
          isDark ? AppColorTokens.bloomDarkBase : AppColorTokens.bloomBase,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const BloomMascot(
                  size: 92,
                  bob: true,
                  pulseRing: true,
                  borderRadius: 34,
                ),
                const SizedBox(height: 24),
                Text(
                  'Inbox Zero!',
                  style: AppTheme.bloomDisplay(
                    24,
                    FontWeight.w700,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextPrimary
                        : AppColorTokens.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You sorted all transactions for today.',
                  style: AppTheme.bloomDisplay(
                    14,
                    FontWeight.w400,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextSecondary
                        : AppColorTokens.inkSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // Streak Banner
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColorTokens.bloomGold.withValues(alpha: 0.18)
                        : const Color(0xFFFFF0D6),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.local_fire_department_rounded,
                        size: 18,
                        color: AppColorTokens.bloomGold,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$streak day streak maintained!',
                        style: AppTheme.bloomDisplay(
                          14,
                          FontWeight.w600,
                          color: isDark
                              ? AppColorTokens.bloomGold
                              : const Color(0xFF8A5A00),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

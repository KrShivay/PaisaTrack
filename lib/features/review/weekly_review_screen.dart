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
import '../transactions/transaction_detail_screen.dart';
import '../transactions/transactions_providers.dart';
import 'weekly_review_providers.dart';

/// Redesigned Bloom Sort screen: Tinder-style card swipe review with
/// Card/List toggle, Skip action, classifier info, error handling,
/// and Inbox Zero state.
class WeeklyReviewScreen extends ConsumerStatefulWidget {
  const WeeklyReviewScreen({super.key});

  @override
  ConsumerState<WeeklyReviewScreen> createState() => _WeeklyReviewScreenState();
}

class _WeeklyReviewScreenState extends ConsumerState<WeeklyReviewScreen> {
  double _dragDx = 0.0;
  int _cursor = 0;
  List<TransactionReviewItem>? _stableQueue;
  int? _totalInitialCount;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final queueAsync = ref.watch(reviewQueueProvider);
    final viewState = ref.watch(reviewViewProvider);

    return queueAsync.when(
      loading: () => Scaffold(
        backgroundColor:
            isDark ? AppColorTokens.bloomDarkBase : AppColorTokens.bloomBase,
        body: const Center(child: BloomSkeleton(width: 280, height: 160)),
      ),
      error: (error, _) => _ErrorView(
        isDark: isDark,
        error: error,
        onRetry: () => ref.invalidate(reviewQueueProvider),
      ),
      data: (items) {
        _stableQueue ??= List.of(items);
        _totalInitialCount ??= _stableQueue!.length;
        final queue = _stableQueue!;
        final skippedIds = viewState.skippedIds;

        if (queue.isEmpty) {
          return _InboxZeroView(isDark: isDark);
        }

        // All remaining items are skipped — prompt to review them.
        if (skippedIds.isNotEmpty &&
            queue.every((i) => skippedIds.contains(i.id))) {
          return _SkippedSummaryView(
            isDark: isDark,
            skippedCount: skippedIds.length,
            onReview: () {
              setState(() => _cursor = 0);
              ref.read(reviewViewProvider.notifier).clearSkipped();
            },
          );
        }

        final safeIndex = _cursor.clamp(0, queue.length - 1);
        final resolvedCount = _totalInitialCount! - queue.length;
        final skippedCount = skippedIds.length;

        if (viewState.viewMode == ReviewViewMode.list) {
          return _ListView(
            items: queue,
            isDark: isDark,
            onConfirm: _confirmItem,
            onRecategorize: _recategorizeItem,
            onSkip: _skipItem,
          );
        }

        return _buildCardView(
          queue,
          safeIndex,
          queue.length,
          isDark,
          resolvedCount: resolvedCount,
          skippedCount: skippedCount,
          totalInitialCount: _totalInitialCount!,
        );
      },
    );
  }

  Widget _buildCardView(
    List<TransactionReviewItem> activeItems,
    int index,
    int totalCount,
    bool isDark, {
    required int resolvedCount,
    required int skippedCount,
    required int totalInitialCount,
  }) {
    final item = activeItems[index];
    final remainingCount = activeItems.length;

    return Scaffold(
      backgroundColor:
          isDark ? AppColorTokens.bloomDarkBase : AppColorTokens.bloomBase,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              // Header Row: Title + counter + view mode toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
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
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // View mode toggle
                      _ViewModeToggle(isDark: isDark),
                      const SizedBox(width: 8),
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
                          '${index + 1} of $remainingCount',
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
                ],
              ),
              const SizedBox(height: 12),
              _SortProgressBar(
                total: totalInitialCount,
                resolved: resolvedCount,
                skipped: skippedCount,
                isDark: isDark,
              ),
              const SizedBox(height: 12),

              // Swipeable Card Container
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setState(() => _dragDx += details.delta.dx);
                    },
                    onPanEnd: (details) {
                      if (_dragDx > 100) {
                        _goBack();
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
                          onTap: () => _openDetailSheet(context, item),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Action Buttons Row (Back / Change category / Skip / Keep)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Back button — moves cursor to previous card (no-op at 0)
                  _ActionButton(
                    icon: Icons.arrow_back_rounded,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextSecondary
                        : AppColorTokens.inkSecondary,
                    bgColor: isDark
                        ? AppColorTokens.bloomDarkCard
                        : AppColorTokens.bloomChip,
                    onTap: _goBack,
                    isDark: isDark,
                    size: 46,
                  ),
                  // Change category button (Gold)
                  _ActionButton(
                    icon: Icons.sell_outlined,
                    color: AppColorTokens.bloomGold,
                    bgColor: isDark
                        ? AppColorTokens.bloomGold.withValues(alpha: 0.18)
                        : const Color(0xFFFFF0D6),
                    onTap: () => _recategorizeItem(item),
                    isDark: isDark,
                  ),
                  // Skip button (Neutral)
                  _ActionButton(
                    icon: Icons.skip_next_rounded,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextSecondary
                        : AppColorTokens.inkSecondary,
                    bgColor: isDark
                        ? AppColorTokens.bloomDarkCard
                        : AppColorTokens.bloomChip,
                    onTap: () => _skipItem(item),
                    isDark: isDark,
                    size: 50,
                  ),
                  // Keep button (Emerald)
                  _ActionButton(
                    icon: Icons.check_rounded,
                    color: AppColorTokens.bloomEmerald,
                    bgColor: isDark
                        ? AppColorTokens.bloomEmerald.withValues(alpha: 0.18)
                        : const Color(0xFFD3F2E4),
                    onTap: () => _confirmItem(item),
                    isDark: isDark,
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

  Future<void> _openDetailSheet(
    BuildContext context,
    TransactionReviewItem item,
  ) async {
    await showBloomFullScreenSheet<void>(
      context: context,
      showClose: true,
      builder: (ctx) => TransactionDetailScreen(txnId: item.id),
    );
    if (!mounted) return;
    // Refresh the item in _stableQueue with any edits applied in the detail sheet.
    final updatedItems = ref.read(reviewQueueProvider).valueOrNull;
    if (updatedItems == null || _stableQueue == null) return;
    final idx = _stableQueue!.indexWhere((i) => i.id == item.id);
    if (idx == -1) return;
    final updated = updatedItems.firstWhere(
      (i) => i.id == item.id,
      orElse: () => _stableQueue![idx],
    );
    setState(() => _stableQueue![idx] = updated);
  }

  void _goBack() {
    setState(() {
      if (_cursor > 0) _cursor--;
    });
  }

  void _skipItem(TransactionReviewItem item) {
    ref.read(reviewViewProvider.notifier).skipItem(item.id);
    setState(() {
      final len = _stableQueue?.length ?? 0;
      if (_cursor < len - 1) _cursor++;
    });
  }

  Future<void> _confirmItem(TransactionReviewItem item) async {
    final originalIdx =
        _stableQueue?.indexWhere((i) => i.id == item.id) ?? -1;
    setState(() {
      if (originalIdx != -1) {
        _stableQueue!.removeAt(originalIdx);
        _cursor =
            _cursor.clamp(0, math.max(0, _stableQueue!.length - 1));
      }
    });

    try {
      final dbAsync = ref.read(appDatabaseProvider);
      final database = dbAsync.valueOrNull ??
          (dbAsync.hasError ? null : await ref.read(appDatabaseProvider.future));
      if (database != null) {
        final repo = ref.read(transactionRepositoryProvider(database));
        await repo.updateWithFeedback(
          txnId: item.id,
          status: const Value('confirmed'),
          context: 'sort_confirm',
        );
      }

      ref.read(undoControllerProvider.notifier).pushUndo(
            UndoToken(
              id: 'sort_confirm_${item.id}',
              message: 'Marked confirmed',
              undoAction: () async {
                if (mounted) {
                  setState(() {
                    final insertAt =
                        originalIdx.clamp(0, _stableQueue!.length);
                    _stableQueue!.insert(insertAt, item);
                    _cursor = insertAt;
                  });
                }
                if (database != null) {
                  final repo = ref.read(transactionRepositoryProvider(database));
                  await repo.updateWithFeedback(
                    txnId: item.id,
                    status: const Value('needs_review'),
                    context: 'undo_sort',
                  );
                }
              },
            ),
          );
    } catch (e) {
      if (mounted) {
        setState(() {
          if (originalIdx != -1) {
            final insertAt =
                originalIdx.clamp(0, _stableQueue!.length);
            _stableQueue!.insert(insertAt, item);
            _cursor = insertAt;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to confirm transaction: $e'),
          ),
        );
      }
    }
  }

  Future<void> _recategorizeItem(TransactionReviewItem item) async {
    final categories = await ref.read(categoryListProvider.future);
    if (!mounted) return;
    final chosen = await showBloomFullScreenSheet<Category>(
      context: context,
      showBack: true,
      builder: (context) => CategoryPickerSheet(
        categories: categories,
        title: 'Change Category',
      ),
    );
    if (chosen == null || !mounted) return;

    final originalIdx =
        _stableQueue?.indexWhere((i) => i.id == item.id) ?? -1;
    setState(() {
      if (originalIdx != -1) {
        _stableQueue!.removeAt(originalIdx);
        _cursor =
            _cursor.clamp(0, math.max(0, _stableQueue!.length - 1));
      }
    });

    try {
      final dbAsync = ref.read(appDatabaseProvider);
      final database = dbAsync.valueOrNull ??
          (dbAsync.hasError ? null : await ref.read(appDatabaseProvider.future));
      final prevCategory = item.categoryId;

      if (database != null) {
        final repo = ref.read(transactionRepositoryProvider(database));
        await repo.updateWithFeedback(
          txnId: item.id,
          categoryId: Value(chosen.id),
          context: 'sort_categorize',
        );
      }

      ref.read(undoControllerProvider.notifier).pushUndo(
            UndoToken(
              id: 'sort_cat_${item.id}',
              message: 'Filed under ${chosen.name}',
              undoAction: () async {
                if (mounted) {
                  setState(() {
                    final insertAt =
                        originalIdx.clamp(0, _stableQueue!.length);
                    _stableQueue!.insert(insertAt, item);
                    _cursor = insertAt;
                  });
                }
                if (database != null) {
                  final repo = ref.read(transactionRepositoryProvider(database));
                  await repo.updateWithFeedback(
                    txnId: item.id,
                    categoryId: Value(prevCategory),
                    context: 'undo_sort',
                  );
                }
              },
            ),
          );
    } catch (e) {
      if (mounted) {
        setState(() {
          if (originalIdx != -1) {
            final insertAt =
                originalIdx.clamp(0, _stableQueue!.length);
            _stableQueue!.insert(insertAt, item);
            _cursor = insertAt;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update category: $e'),
          ),
        );
      }
    }
  }
}

// ── Skipped Summary View ──────────────────────────────────────────────

class _SkippedSummaryView extends StatelessWidget {
  const _SkippedSummaryView({
    required this.isDark,
    required this.skippedCount,
    required this.onReview,
  });

  final bool isDark;
  final int skippedCount;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
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
                Icon(
                  Icons.playlist_play_rounded,
                  size: 56,
                  color: isDark
                      ? AppColorTokens.bloomGold
                      : const Color(0xFF8A5A00),
                ),
                const SizedBox(height: 16),
                Text(
                  '$skippedCount skipped',
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
                  'Review them now?',
                  style: AppTheme.bloomDisplay(
                    14,
                    FontWeight.w400,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextSecondary
                        : AppColorTokens.inkSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onReview,
                  child: const Text('Review skipped'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sort Progress Bar ─────────────────────────────────────────────────

class _SortProgressBar extends StatelessWidget {
  const _SortProgressBar({
    required this.total,
    required this.resolved,
    required this.skipped,
    required this.isDark,
  });

  final int total;
  final int resolved;
  final int skipped;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox.shrink();
    final remaining = (total - resolved - skipped).clamp(0, total);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: Row(
          children: [
            if (resolved > 0)
              Expanded(
                flex: resolved,
                child: const ColoredBox(color: AppColorTokens.bloomEmerald),
              ),
            if (skipped > 0)
              Expanded(
                flex: skipped,
                child: const ColoredBox(color: AppColorTokens.bloomGold),
              ),
            if (remaining > 0)
              Expanded(
                flex: remaining,
                child: ColoredBox(
                  color: isDark
                      ? AppColorTokens.bloomDarkCard
                      : AppColorTokens.bloomChip,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── View Mode Toggle ──────────────────────────────────────────────────

class _ViewModeToggle extends ConsumerWidget {
  const _ViewModeToggle({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewState = ref.watch(reviewViewProvider);
    final isCard = viewState.viewMode == ReviewViewMode.card;

    return GestureDetector(
      onTap: () {
        ref.read(reviewViewProvider.notifier).setViewMode(
              isCard ? ReviewViewMode.list : ReviewViewMode.card,
            );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:
              isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomChip,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          isCard ? Icons.view_list_rounded : Icons.view_carousel_rounded,
          size: 18,
          color: isDark
              ? AppColorTokens.bloomDarkTextSecondary
              : AppColorTokens.inkSecondary,
        ),
      ),
    );
  }
}

// ── Action Button ─────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.onTap,
    required this.isDark,
    this.size = 58,
  });

  final IconData icon;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;
  final bool isDark;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bgColor,
          boxShadow: AppColorTokens.bloomSortCardShadow,
        ),
        child: Center(
          child: Icon(icon, size: 24, color: color),
        ),
      ),
    );
  }
}

// ── Sort Card ─────────────────────────────────────────────────────────

class _SortCard extends StatelessWidget {
  const _SortCard({
    required this.item,
    required this.dragDx,
    required this.isDark,
    this.onTap,
  });

  final TransactionReviewItem item;
  final double dragDx;
  final bool isDark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard;
    final border = isDark
        ? Border.all(color: AppColorTokens.bloomDarkOutline, width: 1)
        : null;

    final isSwipingRight = dragDx > 40;
    final isSwipingLeft = dragDx < -40;

    return GestureDetector(
      onTap: onTap,
      child: Container(
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
                color: isDark
                    ? AppColorTokens.bloomDarkCard
                    : AppColorTokens.bloomChip,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back_rounded,
                    size: 14,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextSecondary
                        : AppColorTokens.inkSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'BACK',
                    style: AppTheme.bloomDisplay(
                      14,
                      FontWeight.w700,
                      color: isDark
                          ? AppColorTokens.bloomDarkTextSecondary
                          : AppColorTokens.inkSecondary,
                    ),
                  ),
                ],
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
            iconName: item.categoryIcon,
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

          // Low-trust parse indicator
          if (item.isLowTrustParse)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColorTokens.bloomGold.withValues(alpha: 0.18)
                    : const Color(0xFFFFF0D6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Low confidence parse — verify details',
                style: AppTheme.bloomDisplay(
                  11,
                  FontWeight.w500,
                  color: isDark
                      ? AppColorTokens.bloomGold
                      : const Color(0xFF8A5A00),
                ),
              ),
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

// ── List View Mode ────────────────────────────────────────────────────

class _ListView extends StatelessWidget {
  const _ListView({
    required this.items,
    required this.isDark,
    required this.onConfirm,
    required this.onRecategorize,
    required this.onSkip,
  });

  final List<TransactionReviewItem> items;
  final bool isDark;
  final ValueChanged<TransactionReviewItem> onConfirm;
  final ValueChanged<TransactionReviewItem> onRecategorize;
  final ValueChanged<TransactionReviewItem> onSkip;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          isDark ? AppColorTokens.bloomDarkBase : AppColorTokens.bloomBase,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
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
                        '${items.length} transactions to review',
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
                  _ViewModeToggle(isDark: isDark),
                ],
              ),
            ),

            // List
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _ReviewListRow(
                    item: item,
                    isDark: isDark,
                    onConfirm: () => onConfirm(item),
                    onRecategorize: () => onRecategorize(item),
                    onSkip: () => onSkip(item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewListRow extends StatelessWidget {
  const _ReviewListRow({
    required this.item,
    required this.isDark,
    required this.onConfirm,
    required this.onRecategorize,
    required this.onSkip,
  });

  final TransactionReviewItem item;
  final bool isDark;
  final VoidCallback onConfirm;
  final VoidCallback onRecategorize;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard;

    return Dismissible(
      key: ValueKey('review_${item.id}'),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: AppColorTokens.bloomEmerald,
          borderRadius: BorderRadius.circular(AppRadius.bloomRow),
        ),
        child: const Icon(Icons.check, color: Colors.white),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColorTokens.bloomGold,
          borderRadius: BorderRadius.circular(AppRadius.bloomRow),
        ),
        child: const Icon(Icons.sell_outlined, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onConfirm();
        } else {
          onRecategorize();
        }
        return false;
      },
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
              iconName: item.categoryIcon,
              size: 36,
              borderRadius: 13,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayName,
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
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        item.categoryName ?? 'Uncategorised',
                        style: AppTheme.bloomDisplay(
                          11,
                          FontWeight.w400,
                          color: isDark
                              ? AppColorTokens.bloomDarkTextTertiary
                              : AppColorTokens.inkTertiary,
                        ),
                      ),
                      if (item.isLowTrustParse) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 12,
                          color: AppColorTokens.bloomGold,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            BloomAmount(
              amount: item.direction == TransactionDirection.debit
                  ? -item.amount
                  : item.amount,
              size: 15,
              weight: FontWeight.w500,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error View ────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.isDark,
    required this.error,
    required this.onRetry,
  });

  final bool isDark;
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          isDark ? AppColorTokens.bloomDarkBase : AppColorTokens.bloomBase,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: isDark
                      ? AppColorTokens.bloomDarkTextTertiary
                      : AppColorTokens.inkTertiary,
                ),
                const SizedBox(height: 12),
                Text(
                  'Could not load review queue',
                  style: AppTheme.bloomDisplay(
                    15,
                    FontWeight.w600,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextPrimary
                        : AppColorTokens.ink,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Something went wrong loading your transactions.',
                  style: AppTheme.bloomDisplay(
                    12,
                    FontWeight.w400,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextSecondary
                        : AppColorTokens.inkSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                  onPressed: onRetry,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Inbox Zero View ───────────────────────────────────────────────────

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
                      Flexible(
                        child: Text(
                          '$streak day streak maintained!',
                          style: AppTheme.bloomDisplay(
                            14,
                            FontWeight.w600,
                            color: isDark
                                ? AppColorTokens.bloomGold
                                : const Color(0xFF8A5A00),
                          ),
                          overflow: TextOverflow.ellipsis,
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

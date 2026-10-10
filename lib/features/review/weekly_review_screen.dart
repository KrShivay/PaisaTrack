import 'dart:math' as math;
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_theme.dart';
import '../../core/undo/undo_controller.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../../core/widgets/category_picker_sheet.dart';
import '../../data/db/database.dart' show Category, Transaction;
import '../../data/db/database_provider.dart';
import '../../data/models/normalized_transaction_record.dart';
import '../../data/payee_display_name.dart';
import '../../data/repositories/sms_disposition_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../transactions/detail/upi_qr_action.dart';
import '../../enrichment/categorizer.dart';
import '../../enrichment/stored_transaction_record.dart';
import '../../intelligence/derived_reads_service.dart';
import '../settings/app_settings.dart';
import '../transactions/transaction_correction_sheet.dart';
import '../transactions/transaction_detail_screen.dart';
import '../transactions/transaction_correction_controller.dart';
import '../transactions/transactions_providers.dart';
import 'review_list_row.dart';
import 'weekly_review_providers.dart';

typedef _RemovedCard = ({
  int index,
  ({String categoryId, String? previous})? guess,
});

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

  /// Cards whose category guess is being recomputed after an edit (T-154b).
  final _refreshingGuess = <String>{};

  /// Cards whose recomputed guess failed; Keep stays off until the user
  /// chooses a category.
  final _guessFailed = <String>{};

  /// Recomputed guesses not yet stored, with the stored category they would
  /// replace so Undo can restore it.
  final _refreshedGuess = <String, ({String categoryId, String? previous})>{};

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
            onOpen: (item) => _openDetailSheet(context, item),
            keepBlocked: _keepBlocked,
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
    final compactLandscape =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    final card = GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() => _dragDx += details.delta.dx);
      },
      onHorizontalDragEnd: (details) {
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
            compactLandscape: compactLandscape,
            guessNote: _refreshingGuess.contains(item.id)
                ? 'Updating guess…'
                : _guessFailed.contains(item.id)
                    ? "Couldn't update the guess. Choose a category."
                    : _refreshedGuess.containsKey(item.id)
                        ? 'Guess updated for the corrected payee'
                        : null,
            onTap: () => _openDetailSheet(context, item),
          ),
        ),
      ),
    );

    final notRight = TextButton.icon(
      onPressed: () => _showNotRight(item),
      icon: const Icon(Icons.flag_outlined, size: 18),
      label: const Text('Not right?'),
    );

    return Scaffold(
      backgroundColor:
          isDark ? AppColorTokens.bloomDarkBase : AppColorTokens.bloomBase,
      body: SafeArea(
        bottom: compactLandscape,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 20,
            vertical: compactLandscape ? 4 : 16,
          ),
          child: Column(
            children: [
              // Keep the decision controls visible while the review content
              // scrolls on short or large-text screens.
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                                if (!compactLandscape) ...[
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
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
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
                      SizedBox(height: compactLandscape ? 4 : 12),
                      if (!compactLandscape) ...[
                        _SortProgressBar(
                          total: totalInitialCount,
                          resolved: resolvedCount,
                          skipped: skippedCount,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 12),
                      ],
                      card,
                      if (compactLandscape)
                        notRight
                      else ...[
                        const SizedBox(height: 12),
                        notRight,
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),

              // Action Buttons Row (Back / Change category / Skip / Keep)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Back button — moves cursor to previous card (no-op at 0)
                  _ActionButton(
                    icon: Icons.arrow_back_rounded,
                    semanticLabel: 'Previous transaction',
                    color: isDark
                        ? AppColorTokens.bloomDarkTextSecondary
                        : AppColorTokens.inkSecondary,
                    bgColor: isDark
                        ? AppColorTokens.bloomDarkCard
                        : AppColorTokens.bloomChip,
                    onTap: index == 0 ? null : _goBack,
                    isDark: isDark,
                    size: compactLandscape ? 48 : 50,
                  ),
                  // Change category button (Gold)
                  _ActionButton(
                    icon: Icons.sell_outlined,
                    semanticLabel: 'Change category',
                    color: AppColorTokens.bloomGold,
                    bgColor: isDark
                        ? AppColorTokens.bloomGold.withValues(alpha: 0.18)
                        : const Color(0xFFFFF0D6),
                    onTap: () => _recategorizeItem(item),
                    isDark: isDark,
                    size: compactLandscape ? 48 : 58,
                  ),
                  // Keep button (Emerald); disabled while the guess for an
                  // edited card is recomputed (T-154b).
                  _ActionButton(
                    icon: Icons.check_rounded,
                    semanticLabel: 'Keep',
                    color: AppColorTokens.bloomEmerald,
                    bgColor: isDark
                        ? AppColorTokens.bloomEmerald.withValues(alpha: 0.18)
                        : const Color(0xFFD3F2E4),
                    onTap:
                        _keepBlocked(item.id) ? null : () => _confirmItem(item),
                    isDark: isDark,
                    size: compactLandscape ? 48 : 58,
                  ),
                  // Skip button (Neutral)
                  _ActionButton(
                    icon: Icons.arrow_forward_rounded,
                    semanticLabel: 'Skip to next transaction',
                    color: isDark
                        ? AppColorTokens.bloomDarkTextSecondary
                        : AppColorTokens.inkSecondary,
                    bgColor: isDark
                        ? AppColorTokens.bloomDarkCard
                        : AppColorTokens.bloomChip,
                    onTap: () => _skipItem(item),
                    isDark: isDark,
                    size: compactLandscape ? 48 : 50,
                  ),
                ],
              ),
              if (!compactLandscape)
                SizedBox(
                  height: BloomBottomInset.contentPadding(context),
                ),
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
    if (await _refreshGuessIfEdited(item) || !mounted) return;
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

  bool _keepBlocked(String id) =>
      _refreshingGuess.contains(id) || _guessFailed.contains(id);

  /// Recomputes the category guess when an edit changed what the guess was
  /// computed from, so Keep never confirms a guess for a corrected-away payee
  /// (T-154b). Read path only: the guess is stored on Keep, without feedback.
  /// A category the user chose in the meantime always wins. Returns whether
  /// the card was updated here.
  Future<bool> _refreshGuessIfEdited(TransactionReviewItem before) async {
    final database = await ref.read(appDatabaseProvider.future);
    final txn = await (database.select(database.transactions)
          ..where((row) => row.id.equals(before.id)))
        .getSingleOrNull();
    if (txn == null || !mounted) return false;
    final storedBefore = _refreshedGuess[txn.id]?.previous ?? before.categoryId;
    final payeeChanged = txn.merchantRaw != before.merchantRaw;
    final categoryChosen = txn.categoryId != storedBefore;
    if (!categoryChosen &&
        !payeeChanged &&
        txn.amount == before.amount &&
        txn.direction == before.direction.wireName) {
      return false;
    }
    final categories = await ref.read(categoryListProvider.future);
    Category? categoryFor(String? id) =>
        categories.where((c) => c.id == id).firstOrNull;
    if (!mounted) return false;
    if (categoryChosen) {
      // The user picked a category: show and keep it, never a guess.
      final chosen = categoryFor(txn.categoryId);
      setState(() {
        _refreshedGuess.remove(txn.id);
        _guessFailed.remove(txn.id);
        _replaceItem(
          before,
          txn,
          payeeChanged: payeeChanged,
          categoryId: txn.categoryId,
          categoryName: chosen?.name,
          categoryIcon: chosen?.icon,
        );
      });
      return true;
    }

    setState(() {
      _refreshingGuess.add(txn.id);
      _guessFailed.remove(txn.id);
    });
    try {
      final categorizer = await ref.read(categorizerProvider.future);
      // The merchant link still points at the old payee after a correction.
      final guess = await categorizer.categorize(
        normalizedRecordOf(txn),
        merchantId: payeeChanged ? null : txn.merchantId,
      );
      if (!mounted) return true;
      final category = categoryFor(guess.categoryId);
      setState(() {
        _refreshedGuess[txn.id] =
            (categoryId: guess.categoryId, previous: storedBefore);
        _replaceItem(
          before,
          txn,
          payeeChanged: payeeChanged,
          categoryId: guess.categoryId,
          categoryName: category?.name,
          categoryIcon: category?.icon,
        );
      });
    } catch (_) {
      if (mounted) setState(() => _guessFailed.add(txn.id));
    } finally {
      if (mounted) setState(() => _refreshingGuess.remove(txn.id));
    }
    return true;
  }

  void _replaceItem(
    TransactionReviewItem item,
    Transaction txn, {
    required bool payeeChanged,
    required String? categoryId,
    String? categoryName,
    String? categoryIcon,
  }) {
    final index = _stableQueue?.indexWhere((i) => i.id == item.id) ?? -1;
    if (index == -1) return;
    _stableQueue![index] = TransactionReviewItem(
      id: item.id,
      ts: item.ts,
      amount: txn.amount,
      currencyCode: txn.currencyCode,
      currencySymbol: txn.currencySymbol,
      direction: txn.direction == 'credit'
          ? TransactionDirection.credit
          : TransactionDirection.debit,
      // A corrected payee no longer matches the old merchant's label.
      displayName: payeeChanged
          ? payeeDisplayName(
              merchantRaw: txn.merchantRaw,
              counterpartyVpa: txn.counterpartyVpa,
              description: txn.description,
            )
          : item.displayName,
      categoryName: categoryName,
      categoryId: categoryId,
      categoryIcon: categoryIcon,
      status: item.status,
      merchantRaw: txn.merchantRaw,
      counterpartyVpa: txn.counterpartyVpa,
      counterpartyKey: item.counterpartyKey,
      isLowTrustParse: item.isLowTrustParse,
    );
  }

  /// Quick corrections for the frequent cases without a detail round trip.
  Future<void> _showNotRight(TransactionReviewItem item) async {
    final database = await ref.read(appDatabaseProvider.future);
    final txn = await (database.select(database.transactions)
          ..where((row) => row.id.equals(item.id)))
        .getSingleOrNull();
    if (txn == null || !mounted) return;
    final choice = await showBloomModalSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note_rounded),
              title: const Text('Wrong payee or amount'),
              onTap: () => Navigator.of(sheetContext).pop('parse'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded),
              title: const Text('Not a spend (transfer or refund)'),
              onTap: () => Navigator.of(sheetContext).pop('transfer'),
            ),
            if (txn.smsId != null)
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('Duplicate or not a transaction'),
                onTap: () => Navigator.of(sheetContext).pop('not_txn'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'parse':
        await showBloomModalSheet<bool>(
          context: context,
          isScrollControlled: true,
          builder: (_) => TransactionCorrectionSheet(
            txnId: item.id,
            initialAmount: txn.amount,
            initialDirection: txn.direction,
            initialMerchant: txn.merchantRaw,
          ),
        );
        if (mounted) await _refreshGuessIfEdited(item);
      case 'transfer':
        await _fileUnder(
          item,
          categoryId: 'transfers',
          categoryName: 'Transfers',
          context: 'sort_not_spend',
        );
      case 'not_txn':
        await _markNotTransaction(item, txn);
    }
  }

  Future<void> _markNotTransaction(
    TransactionReviewItem item,
    Transaction txn,
  ) async {
    final database = await ref.read(appDatabaseProvider.future);
    final dispositions = SmsDispositionRepository(
      database,
      derivedReadsService: await ref.read(derivedReadsServiceProvider.future),
    );
    final removed = _removeFromQueue(item);
    try {
      await dispositions.markNotTransaction(txn);
    } catch (e) {
      _restoreToQueue(item, removed);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to mark as not a transaction: $e')),
        );
      }
      return;
    }
    ref.read(undoControllerProvider.notifier).pushUndo(
          UndoToken(
            id: 'sort_not_txn_${item.id}',
            message: 'Marked as not a transaction',
            undoAction: () async {
              _restoreToQueue(item, removed);
              await dispositions.restore(txn.smsId!);
            },
          ),
        );
  }

  /// Removes a card; the result restores its position and any recomputed
  /// guess on Undo or failure.
  _RemovedCard _removeFromQueue(TransactionReviewItem item) {
    final removed = (
      index: _stableQueue?.indexWhere((i) => i.id == item.id) ?? -1,
      guess: _refreshedGuess[item.id],
    );
    setState(() {
      _refreshedGuess.remove(item.id);
      if (removed.index != -1) {
        _stableQueue!.removeAt(removed.index);
        _cursor = _cursor.clamp(0, math.max(0, _stableQueue!.length - 1));
      }
    });
    return removed;
  }

  void _restoreToQueue(TransactionReviewItem item, _RemovedCard removed) {
    if (!mounted || removed.index == -1) return;
    setState(() {
      final insertAt = removed.index.clamp(0, _stableQueue!.length);
      _stableQueue!.insert(insertAt, item);
      _cursor = insertAt;
      if (removed.guess case final guess?) _refreshedGuess[item.id] = guess;
    });
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

  TransactionCorrectionController get _correctionController =>
      TransactionCorrectionController(
        loadDatabase: () async {
          final dbAsync = ref.read(appDatabaseProvider);
          return dbAsync.valueOrNull ??
              (dbAsync.hasError
                  ? null
                  : await ref.read(appDatabaseProvider.future));
        },
        resolveRepository: (database) =>
            ref.read(transactionRepositoryProvider(database)),
        undoController: ref.read(undoControllerProvider.notifier),
      );

  Future<void> _confirmItem(TransactionReviewItem item) async {
    if (_keepBlocked(item.id)) return;
    final guess = _refreshedGuess[item.id];
    final removed = _removeFromQueue(item);

    try {
      await _correctionController.apply(
        id: 'sort_confirm_${item.id}',
        message: 'Marked confirmed',
        action: (repo) async {
          if (repo == null) return;
          if (guess != null) {
            // Keep stores the recomputed guess the card showed, never the
            // capture-time guess for the corrected-away payee.
            await repo.applyReviewGuess(
              txnId: item.id,
              categoryId: guess.categoryId,
              status: 'confirmed',
            );
          } else {
            await repo.updateWithFeedback(
              txnId: item.id,
              status: const Value('confirmed'),
              context: 'sort_confirm',
            );
          }
        },
        undo: (repo) async {
          _restoreToQueue(item, removed);
          if (repo == null) return;
          if (guess != null) {
            await repo.applyReviewGuess(
              txnId: item.id,
              categoryId: guess.previous,
              status: 'needs_review',
            );
          } else {
            await repo.updateWithFeedback(
              txnId: item.id,
              status: const Value('needs_review'),
              context: 'undo_sort',
            );
          }
        },
      );
    } catch (e) {
      _restoreToQueue(item, removed);
      if (mounted) {
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
    await _fileUnder(
      item,
      categoryId: chosen.id,
      categoryName: chosen.name,
      context: 'sort_categorize',
    );
  }

  /// Applies the user's explicit category choice (a correction with
  /// feedback) and removes the card, with Undo.
  Future<void> _fileUnder(
    TransactionReviewItem item, {
    required String categoryId,
    required String categoryName,
    required String context,
  }) async {
    final prevCategory = _refreshedGuess[item.id]?.previous ?? item.categoryId;
    final removed = _removeFromQueue(item);
    _guessFailed.remove(item.id);

    try {
      await _correctionController.apply(
        id: 'sort_cat_${item.id}',
        message: 'Filed under $categoryName',
        action: (repo) async {
          if (repo != null) {
            await repo.updateWithFeedback(
              txnId: item.id,
              categoryId: Value(categoryId),
              context: context,
            );
          }
        },
        undo: (repo) async {
          _restoreToQueue(item, removed);
          if (repo != null) {
            await repo.updateWithFeedback(
              txnId: item.id,
              categoryId: Value(prevCategory),
              context: 'undo_sort',
            );
          }
        },
      );
    } catch (e) {
      _restoreToQueue(item, removed);
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
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
    final label = isCard ? 'Card view' : 'List view';
    final nextView = isCard ? 'list' : 'card';

    void toggleView() {
      ref.read(reviewViewProvider.notifier).setViewMode(
            isCard ? ReviewViewMode.list : ReviewViewMode.card,
          );
    }

    return Semantics(
      container: true,
      label: label,
      button: true,
      selected: true,
      onTap: toggleView,
      hint: 'Switch to $nextView view',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: toggleView,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDark
                    ? AppColorTokens.bloomDarkCard
                    : AppColorTokens.bloomChip,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                isCard ? Icons.view_list_rounded : Icons.view_carousel_rounded,
                size: 20,
                color: isDark
                    ? AppColorTokens.bloomDarkTextSecondary
                    : AppColorTokens.inkSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Action Button ─────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.semanticLabel,
    required this.color,
    required this.bgColor,
    required this.onTap,
    required this.isDark,
    this.size = 58,
  });

  final IconData icon;
  final Color color;
  final Color bgColor;

  /// Null disables the button.
  final VoidCallback? onTap;
  final bool isDark;
  final double size;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticLabel,
      button: true,
      enabled: onTap != null,
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Opacity(
            opacity: onTap == null ? 0.4 : 1,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bgColor,
                boxShadow: AppColorTokens.bloomSortCardShadow,
              ),
              child: Center(child: Icon(icon, size: 24, color: color)),
            ),
          ),
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
    required this.compactLandscape,
    this.guessNote,
    this.onTap,
  });

  final TransactionReviewItem item;
  final double dragDx;
  final bool isDark;
  final bool compactLandscape;

  /// Shown while, or after, the guess is recomputed for an edited card.
  final String? guessNote;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard;
    final border = isDark
        ? Border.all(color: AppColorTokens.bloomDarkOutline, width: 1)
        : null;

    final isSwipingRight = dragDx > 40;
    final isSwipingLeft = dragDx < -40;
    final amount = formatSourceAmount(
      item.direction == TransactionDirection.debit ? -item.amount : item.amount,
      currencyCode: item.currencyCode,
      currencySymbol: item.currencySymbol,
    );
    final cardDirection =
        item.direction == TransactionDirection.debit ? 'Expense' : 'Income';
    final cardLabel = '${item.displayName}, '
        '${item.categoryName ?? 'Uncategorised'}, $cardDirection, $amount, '
        '${_formatTime(item.ts)}, ${item.status}'
        '${item.isLowTrustParse ? ', Low confidence parse — verify details' : ''}';

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: cardLabel,
      button: true,
      enabled: onTap != null,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(compactLandscape ? 12 : 24),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(26),
            border: border,
            boxShadow: AppColorTokens.bloomSortCardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag Stamp Overlay
                    if (isSwipingRight)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
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
                              size: 16,
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
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
                      SizedBox(height: compactLandscape ? 0 : 28),

                    SizedBox(height: compactLandscape ? 4 : 12),
                    // Category Tile 52px
                    BloomCategoryTile(
                      categoryId: item.categoryId,
                      iconName: item.categoryIcon,
                      size: compactLandscape ? 44 : 52,
                      borderRadius: compactLandscape ? 14 : 18,
                    ),
                    SizedBox(height: compactLandscape ? 4 : 16),

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
                    if (guessNote != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          guessNote!,
                          style: AppTheme.bloomDisplay(
                            11,
                            FontWeight.w600,
                            color: AppColorTokens.bloomEmerald,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 4),

                    // Low-trust parse indicator
                    if (item.isLowTrustParse)
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
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
                      currencyCode: item.currencyCode,
                      currencySymbol: item.currencySymbol,
                      size: 48,
                      weight: FontWeight.w600,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              UpiQrAction(
                counterpartyVpa: item.counterpartyVpa,
                transactionTitle: item.displayName,
              ),
            ],
          ),
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
    required this.onOpen,
    required this.keepBlocked,
  });

  final List<TransactionReviewItem> items;
  final ValueChanged<TransactionReviewItem> onOpen;
  final bool isDark;
  final ValueChanged<TransactionReviewItem> onConfirm;
  final ValueChanged<TransactionReviewItem> onRecategorize;
  final ValueChanged<TransactionReviewItem> onSkip;
  final bool Function(String) keepBlocked;

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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 360;
                  final title = Column(
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
                  );
                  final viewModeToggle = _ViewModeToggle(isDark: isDark);
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        title,
                        Align(
                          alignment: Alignment.centerRight,
                          child: viewModeToggle,
                        ),
                      ],
                    );
                  }
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [title, viewModeToggle],
                  );
                },
              ),
            ),

            // List
            Expanded(
              child: Semantics(
                role: SemanticsRole.list,
                child: ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    0,
                    20,
                    BloomBottomInset.contentPadding(context),
                  ),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ReviewListRow(
                      item: item,
                      isDark: isDark,
                      onOpen: () => onOpen(item),
                      onConfirm: () => onConfirm(item),
                      onRecategorize: () => onRecategorize(item),
                      onSkip: () => onSkip(item),
                      keepEnabled: !keepBlocked(item.id),
                    );
                  },
                ),
              ),
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

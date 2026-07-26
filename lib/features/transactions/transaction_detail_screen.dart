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
import '../../data/repositories/transaction_repository.dart';
import 'transactions_providers.dart';

/// Redesigned Bloom Transaction Detail sheet with hero amount, category editor,
/// and technical SMS provenance disclosure.
class TransactionDetailScreen extends ConsumerStatefulWidget {
  const TransactionDetailScreen({super.key, required this.txnId});

  final String txnId;

  @override
  ConsumerState<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState
    extends ConsumerState<TransactionDetailScreen> {
  final _noteController = TextEditingController();
  bool _seeded = false;
  String? _categoryId;
  String? _categoryName;
  bool _showTechnicalDetails = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _seed(TransactionDetail detail) {
    if (_seeded) return;
    _seeded = true;
    _categoryId = detail.txn.categoryId;
    _noteController.text = detail.txn.description ?? '';
  }

  Future<void> _changeCategory() async {
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

    final database = await ref.read(appDatabaseProvider.future);
    final repo = ref.read(transactionRepositoryProvider(database));
    final prevCategory = _categoryId;

    setState(() {
      _categoryId = chosen.id;
      _categoryName = chosen.name;
    });

    await repo.updateWithFeedback(
      txnId: widget.txnId,
      categoryId: Value(chosen.id),
      context: 'detail_edit',
    );

    ref.read(undoControllerProvider.notifier).pushUndo(
          UndoToken(
            id: 'cat_detail_${widget.txnId}',
            message: 'Category updated to ${chosen.name}',
            undoAction: () async {
              await repo.updateWithFeedback(
                txnId: widget.txnId,
                categoryId: Value(prevCategory),
                context: 'undo_detail',
              );
              if (mounted) {
                setState(() => _categoryId = prevCategory);
              }
            },
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final detailAsync = ref.watch(transactionDetailProvider(widget.txnId));

    return Scaffold(
      backgroundColor:
          isDark ? AppColorTokens.bloomDarkBase : AppColorTokens.bloomBase,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Transaction Detail',
          style: AppTheme.bloomDisplay(
            18,
            FontWeight.w700,
            color: isDark
                ? AppColorTokens.bloomDarkTextPrimary
                : AppColorTokens.ink,
          ),
        ),
      ),
      body: SafeArea(
        child: detailAsync.when(
          data: (detail) {
            if (detail == null) {
              return const Center(child: Text('Transaction not found'));
            }
            _seed(detail);

            final txn = detail.txn;
            final isDebit = txn.direction == 'debit';
            final categoryDisplayName =
                _categoryName ?? detail.categoryName ?? 'Uncategorised';
            final displayName =
                detail.merchantName ?? txn.merchantRaw ?? 'Transaction';
            final date = DateTime.fromMillisecondsSinceEpoch(txn.ts);

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                children: [
                  // Top Header: Category Tile (44px) + Merchant Title
                  Row(
                    children: [
                      BloomCategoryTile(
                        categoryId: _categoryId ?? txn.categoryId,
                        size: 44,
                        borderRadius: 16,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: AppTheme.bloomDisplay(
                                18,
                                FontWeight.w700,
                                color: isDark
                                    ? AppColorTokens.bloomDarkTextPrimary
                                    : AppColorTokens.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatDate(date),
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
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Hero Amount 44px
                  BloomAmount(
                    amount: isDebit ? -txn.amount : txn.amount,
                    size: 44,
                    weight: FontWeight.w600,
                  ),
                  const SizedBox(height: 24),

                  // Metadata Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColorTokens.bloomDarkCard
                          : AppColorTokens.bloomCard,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        // Category Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'CATEGORY',
                                  style: AppTheme.bloomDisplay(
                                    10,
                                    FontWeight.w600,
                                    letterSpacing: 0.1,
                                    color: isDark
                                        ? AppColorTokens.bloomDarkTextTertiary
                                        : AppColorTokens.inkTertiary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  categoryDisplayName,
                                  style: AppTheme.bloomDisplay(
                                    14,
                                    FontWeight.w600,
                                    color: isDark
                                        ? AppColorTokens.bloomDarkTextPrimary
                                        : AppColorTokens.ink,
                                  ),
                                ),
                              ],
                            ),
                            GestureDetector(
                              onTap: _changeCategory,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColorTokens.violetPrimary
                                      : AppColorTokens.ink,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  'Change',
                                  style: AppTheme.bloomDisplay(
                                    12,
                                    FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (txn.accountHint != null &&
                            txn.accountHint!.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Divider(height: 1),
                          ),
                          // Account / Source Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Payment Source',
                                style: AppTheme.bloomDisplay(
                                  13,
                                  FontWeight.w400,
                                  color: isDark
                                      ? AppColorTokens.bloomDarkTextSecondary
                                      : AppColorTokens.inkSecondary,
                                ),
                              ),
                              Text(
                                txn.accountHint!,
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
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Technical SMS Provenance Disclosure
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showTechnicalDetails = !_showTechnicalDetails;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColorTokens.bloomDarkCard
                            : const Color(0xFFF1EFFB),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(
                                  Icons.terminal_rounded,
                                  size: 16,
                                  color: isDark
                                      ? AppColorTokens.bloomDarkTextTertiary
                                      : AppColorTokens.inkTertiary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Technical details & SMS provenance',
                                    style: AppTheme.bloomDisplay(
                                      12,
                                      FontWeight.w500,
                                      color: isDark
                                          ? AppColorTokens
                                              .bloomDarkTextSecondary
                                          : AppColorTokens.inkSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            _showTechnicalDetails
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 18,
                            color: isDark
                                ? AppColorTokens.bloomDarkTextTertiary
                                : AppColorTokens.inkTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (_showTechnicalDetails) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColorTokens.bloomDarkCard
                            : AppColorTokens.bloomCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? AppColorTokens.bloomDarkOutline
                              : AppColorTokens.bloomChip,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PARSED PROVENANCE',
                            style: AppTheme.bloomDisplay(
                              10,
                              FontWeight.w600,
                              letterSpacing: 0.1,
                              color: isDark
                                  ? AppColorTokens.bloomDarkTextTertiary
                                  : AppColorTokens.inkTertiary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Channel: ${txn.channel} · Status: ${txn.status}',
                            style: AppTheme.bloomMono(
                              12,
                              FontWeight.w400,
                              color: isDark
                                  ? AppColorTokens.bloomDarkTextSecondary
                                  : AppColorTokens.inkSecondary,
                            ),
                          ),
                          if (detail.parseConfidence != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              'CONFIDENCE: ${(detail.parseConfidence! * 100).toStringAsFixed(0)}%',
                              style: AppTheme.bloomMono(
                                11,
                                FontWeight.w600,
                                color: AppColorTokens.violetPrimary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            );
          },
          loading: () =>
              const Center(child: BloomSkeleton(width: 260, height: 180)),
          error: (err, _) => Center(child: Text('Error loading detail: $err')),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final h =
        local.hour > 12 ? local.hour - 12 : (local.hour == 0 ? 12 : local.hour);
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'pm' : 'am';
    return '${_shortMonth(local.month)} ${local.day}, ${local.year} · $h:$m $ampm';
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

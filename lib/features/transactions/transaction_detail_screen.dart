import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/category_visuals.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../../core/widgets/category_picker_sheet.dart';
import '../../core/undo/undo_controller.dart';
import '../../data/confidence_payload.dart';
import '../../data/db/database.dart' show Category;
import '../../data/db/database_provider.dart';
import '../../data/models/normalized_transaction_record.dart';
import '../../data/repositories/category_correction.dart';
import '../../data/repositories/transaction_repository.dart';
import 'transaction_correction_sheet.dart';
import 'transactions_providers.dart';

/// Redesigned Bloom Transaction Detail sheet with hero amount, category editor,
/// scope selector, and technical SMS provenance disclosure.
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
  bool _savingNote = false;
  String? _noteError;

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

  Future<void> _saveNote() async {
    setState(() {
      _savingNote = true;
      _noteError = null;
    });

    try {
      final database = await ref.read(appDatabaseProvider.future);
      final repo = ref.read(transactionRepositoryProvider(database));
      await repo.updateWithFeedback(
        txnId: widget.txnId,
        description: Value(_noteController.text.trim()),
        context: 'detail_note_edit',
      );

      if (mounted) {
        setState(() => _savingNote = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Note saved.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _savingNote = false;
          _noteError = 'Failed to save note: ${e.toString()}';
        });
      }
    }
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

    final scope = await showBloomModalSheet<CorrectionScope>(
      context: context,
      builder: (context) => CategoryScopeSelectionSheet(
        categoryName: chosen.name,
      ),
    );
    if (scope == null || !mounted) return;

    final database = await ref.read(appDatabaseProvider.future);
    final repo = ref.read(transactionRepositoryProvider(database));
    final prevCategory = _categoryId;

    setState(() {
      _categoryId = chosen.id;
      _categoryName = chosen.name;
    });

    await repo.correctCategory(
      txnId: widget.txnId,
      categoryId: chosen.id,
      scope: scope,
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

  Future<void> _selectCategoryDirectly(Category chosen) async {
    final database = await ref.read(appDatabaseProvider.future);
    final repo = ref.read(transactionRepositoryProvider(database));
    final prevCategory = _categoryId;

    setState(() {
      _categoryId = chosen.id;
      _categoryName = chosen.name;
    });

    await repo.correctCategory(
      txnId: widget.txnId,
      categoryId: chosen.id,
      scope: CorrectionScope.thisTransaction,
      context: 'detail_chip_edit',
    );

    ref.read(undoControllerProvider.notifier).pushUndo(
          UndoToken(
            id: 'cat_detail_${widget.txnId}',
            message: 'Category updated to ${chosen.name}',
            undoAction: () async {
              if (prevCategory != null) {
                await repo.updateWithFeedback(
                  txnId: widget.txnId,
                  categoryId: Value(prevCategory),
                  context: 'undo_detail',
                );
                if (mounted) {
                  setState(() => _categoryId = prevCategory);
                }
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
            final currentCatId = _categoryId ?? txn.categoryId ?? 'uncategorized';
            final categoryDisplayName =
                _categoryName ?? detail.categoryName ?? 'Uncategorised';
            final displayName =
                detail.merchantName ?? txn.merchantRaw ?? 'Transaction';
            final date = DateTime.fromMillisecondsSinceEpoch(txn.ts);

            final allCategories =
                ref.watch(categoryListProvider).valueOrNull ?? const <Category>[];
            final currentCat = allCategories.firstWhere(
              (c) => c.id == currentCatId,
              orElse: () => Category(
                id: currentCatId,
                name: categoryDisplayName,
                icon: detail.categoryIcon ?? 'category',
                isSpending: true,
                sortOrder: 0,
                isUserCreated: false,
              ),
            );

            final chipCategories = <Category>[currentCat];
            for (final c in allCategories) {
              if (chipCategories.length >= 3) break;
              if (c.id != currentCat.id && c.id != 'uncategorized') {
                chipCategories.add(c);
              }
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                children: [
                  // Top Header: Category Tile (44px) + Merchant Title
                  Row(
                    children: [
                      BloomCategoryTile(
                        categoryId: currentCatId,
                        iconName: detail.categoryIcon,
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
                        // Category Row with Inline Chips (T-148b)
                        Semantics(
                          label: 'Category, $categoryDisplayName, double tap to change',
                          button: true,
                          child: InkWell(
                            onTap: _changeCategory,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'CATEGORY',
                                    style: AppTheme.bloomDisplay(
                                      12,
                                      FontWeight.w700,
                                      letterSpacing: 0.1,
                                      color: isDark
                                          ? AppColorTokens.bloomDarkTextTertiary
                                          : AppColorTokens.inkTertiary,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        for (final cat in chipCategories) ...[
                                          _InlineCategoryChip(
                                            category: cat,
                                            isSelected: cat.id == currentCatId,
                                            isDark: isDark,
                                            onTap: () {
                                              if (cat.id == currentCatId) {
                                                _changeCategory();
                                              } else {
                                                _selectCategoryDirectly(cat);
                                              }
                                            },
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        _MoreCategoryChip(
                                          isDark: isDark,
                                          onTap: _changeCategory,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (txn.accountHint != null &&
                            txn.accountHint!.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Divider(height: 1),
                          ),
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
                  const SizedBox(height: 16),

                  // Exclusion Explanation Banner (T-135c)
                  if (txn.ownedTransferId != null ||
                      (txn.merchantRaw != null &&
                          (txn.merchantRaw!.toUpperCase().contains('CREDIT CARD') ||
                              txn.merchantRaw!.toUpperCase().contains('CARD BILL'))) ||
                      (txn.merchantRaw != null &&
                          (txn.merchantRaw!.toUpperCase().contains('ATM') ||
                              txn.merchantRaw!.toUpperCase().contains('WITHDRAWAL'))) ||
                      txn.isAnalyticsExcluded) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E3A8A).withValues(alpha: 0.3)
                            : const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF3B82F6).withValues(alpha: 0.4)
                              : const Color(0xFFBFDBFE),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: isDark ? const Color(0xFF60A5FA) : Colors.blue.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              txn.ownedTransferId != null
                                  ? 'Self-transfer — excluded from totals to prevent double-counting.'
                                  : (txn.merchantRaw != null &&
                                          (txn.merchantRaw!.toUpperCase().contains('CREDIT CARD') ||
                                              txn.merchantRaw!.toUpperCase().contains('CARD BILL')))
                                      ? 'Credit card bill payment — excluded from totals (card purchases are counted individually).'
                                      : (txn.merchantRaw != null &&
                                              (txn.merchantRaw!.toUpperCase().contains('ATM') ||
                                                  txn.merchantRaw!.toUpperCase().contains('WITHDRAWAL')))
                                          ? 'Cash withdrawal — moved to untracked cash (excluded from category spending).'
                                          : 'Excluded from analytics per settings.',
                              style: AppTheme.bloomDisplay(
                                12,
                                FontWeight.w500,
                                color: isDark
                                    ? AppColorTokens.bloomDarkTextPrimary
                                    : AppColorTokens.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Review Queue Banner (Confirm / Fix)
                  if (txn.status == 'needs_review' ||
                      detail.isLowTrustParse) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColorTokens.warningDark.withValues(alpha: 0.14)
                            : const Color(0xFFFFF8E6),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? AppColorTokens.warningDark
                                  .withValues(alpha: 0.4)
                              : const Color(0xFFFBE6B5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.help_outline_rounded,
                                color: AppColorTokens.warningDark,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  detail.isLowTrustParse
                                      ? 'Low trust parse — please confirm details'
                                      : 'Suggested Category: $categoryDisplayName',
                                  style: AppTheme.bloomDisplay(
                                    13,
                                    FontWeight.w600,
                                    color: isDark
                                        ? AppColorTokens.bloomDarkTextPrimary
                                        : AppColorTokens.ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    final database = await ref
                                        .read(appDatabaseProvider.future);
                                    final repo = ref.read(
                                      transactionRepositoryProvider(
                                        database,
                                      ),
                                    );
                                    await repo.confirm(txnId: widget.txnId);
                                  },
                                  child: const Text('Confirm'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor:
                                        AppColorTokens.violetPrimary,
                                  ),
                                  onPressed: () {
                                    showBloomModalSheet<bool>(
                                      context: context,
                                      isScrollControlled: true,
                                      builder: (context) =>
                                          TransactionCorrectionSheet(
                                        txnId: widget.txnId,
                                        initialAmount: txn.amount,
                                        initialDirection: txn.direction,
                                        initialMerchant: displayName,
                                      ),
                                    );
                                  },
                                  child: const Text('Fix Details'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Note Editor & Save Action
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColorTokens.bloomDarkCard
                          : AppColorTokens.bloomCard,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'NOTE',
                              style: AppTheme.bloomDisplay(
                                10,
                                FontWeight.w600,
                                letterSpacing: 0.1,
                                color: isDark
                                    ? AppColorTokens.bloomDarkTextTertiary
                                    : AppColorTokens.inkTertiary,
                              ),
                            ),
                            TextButton(
                              onPressed: _savingNote ? null : _saveNote,
                              child: _savingNote
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Save Note'),
                            ),
                          ],
                        ),
                        if (_noteError != null) ...[
                          Text(
                            _noteError!,
                            style: AppTheme.bloomDisplay(
                              11,
                              FontWeight.w500,
                              color: AppColorTokens.errorDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        TextField(
                          controller: _noteController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: 'Add a personal note or tag...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: isDark
                                ? AppColorTokens.bloomDarkBase
                                : const Color(0xFFF6F4FE),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Action: Correct Parse Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.edit_note_rounded, size: 18),
                      label: const Text(
                        'Edit Parse Details (Amount/Direction/Payee)',
                      ),
                      onPressed: () {
                        showBloomModalSheet<bool>(
                          context: context,
                          isScrollControlled: true,
                          builder: (context) => TransactionCorrectionSheet(
                            txnId: widget.txnId,
                            initialAmount: txn.amount,
                            initialDirection: txn.direction,
                            initialMerchant: displayName,
                          ),
                        );
                      },
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
                          if (txn.refId != null && txn.refId!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Ref ID: ${txn.refId}',
                              style: AppTheme.bloomMono(12, FontWeight.w400),
                            ),
                          ],
                          if (txn.counterpartyVpa != null &&
                              txn.counterpartyVpa!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'VPA: ${txn.counterpartyVpa}',
                              style: AppTheme.bloomMono(12, FontWeight.w400),
                            ),
                          ],
                          if (txn.balanceAfter != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Balance After: ₹${txn.balanceAfter!.toStringAsFixed(2)}',
                              style: AppTheme.bloomMono(12, FontWeight.w400),
                            ),
                          ],
                          if (detail.parseConfidence != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              'CONFIDENCE: ${(detail.parseConfidence! * 100).toStringAsFixed(0)}% (${detail.isLowTrustParse ? "Low Trust" : "High Trust"})',
                              style: AppTheme.bloomMono(
                                11,
                                FontWeight.w600,
                                color: detail.isLowTrustParse
                                    ? AppColorTokens.warningDark
                                    : AppColorTokens.emerald,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          const Divider(),
                          const SizedBox(height: 8),
                          _SourceMessageEvidenceView(
                            rawSmsBody: detail.rawSmsBody,
                            evidence: parseEvidenceFromJson(txn.evidenceJson),
                            parseSource: txn.parseSource,
                            parseConfidence: detail.parseConfidence,
                            isDark: isDark,
                          ),

                          // Debug Mode Boundary: Raw SMS Body & LLM Json strictly gated
                          if (kDebugMode) ...[
                            const SizedBox(height: 12),
                            const Divider(),
                            Text(
                              'DEBUG EVIDENCE (DEVELOPER ONLY)',
                              style: AppTheme.bloomDisplay(
                                10,
                                FontWeight.w700,
                                color: AppColorTokens.errorDark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SelectableText(
                              'Confidence JSON: ${txn.confidenceJson}',
                              style: AppTheme.bloomMono(10, FontWeight.w400),
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

class _SourceMessageEvidenceView extends StatelessWidget {
  const _SourceMessageEvidenceView({
    required this.rawSmsBody,
    required this.evidence,
    required this.parseSource,
    required this.parseConfidence,
    required this.isDark,
  });

  final String? rawSmsBody;
  final List<FieldEvidence>? evidence;
  final String parseSource;
  final double? parseConfidence;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (rawSmsBody == null || rawSmsBody!.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark
              ? AppColorTokens.bloomDarkCard
              : AppColorTokens.bloomCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Source message purged per retention policy',
          style: AppTheme.bloomDisplay(
            12,
            FontWeight.w400,
            color: isDark
                ? AppColorTokens.bloomDarkTextTertiary
                : AppColorTokens.inkTertiary,
          ),
        ),
      );
    }

    final evList = evidence ?? [];
    if (evList.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHERE THIS CAME FROM',
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
          SelectableText(
            rawSmsBody!,
            style: AppTheme.bloomMono(12, FontWeight.w400),
          ),
        ],
      );
    }

    // Sort evidence spans by start offset
    final sorted = [...evList]..sort((a, b) => a.start.compareTo(b.start));
    final spans = <InlineSpan>[];
    var currentOffset = 0;
    final textLength = rawSmsBody!.length;

    for (final ev in sorted) {
      if (ev.start < currentOffset || ev.start >= textLength) continue;
      if (ev.start > currentOffset) {
        spans.add(
          TextSpan(
            text: rawSmsBody!.substring(currentOffset, ev.start),
          ),
        );
      }
      final end = math.min(ev.end, textLength);
      final verbatimText = rawSmsBody!.substring(ev.start, end);
      final highlightColor = _highlightColorFor(ev.field, isDark);

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: highlightColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              verbatimText,
              style: AppTheme.bloomMono(
                12,
                FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
        ),
      );
      currentOffset = end;
    }
    if (currentOffset < textLength) {
      spans.add(TextSpan(text: rawSmsBody!.substring(currentOffset)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WHERE THIS CAME FROM',
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
        SelectableText.rich(
          TextSpan(
            children: spans,
            style: AppTheme.bloomMono(12, FontWeight.w400),
          ),
        ),
        const SizedBox(height: 10),
        // Field evidence legend badges with parser & confidence per field
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final ev in evList)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColorTokens.bloomDarkBase
                      : const Color(0xFFEFEBFD),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${ev.field}: "${ev.verbatim}" (${ev.extractor}, ${(parseConfidence ?? 1.0) * 100 ~/ 1}%)',
                  style: AppTheme.bloomMono(
                    10,
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
    );
  }

  Color _highlightColorFor(String field, bool isDark) {
    switch (field.toLowerCase()) {
      case 'amount':
        return isDark
            ? AppColorTokens.emerald.withValues(alpha: 0.35)
            : const Color(0xFFD1F4E0);
      case 'direction':
        return isDark
            ? AppColorTokens.violetPrimary.withValues(alpha: 0.35)
            : const Color(0xFFE2D9F3);
      case 'date':
      case 'ts':
        return isDark
            ? AppColorTokens.warningDark.withValues(alpha: 0.35)
            : const Color(0xFFFBE6B5);
      default:
        return isDark
            ? AppColorTokens.royalBlue.withValues(alpha: 0.35)
            : const Color(0xFFD9EEF9);
    }
  }
}

class _InlineCategoryChip extends StatelessWidget {
  const _InlineCategoryChip({
    required this.category,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  final Category category;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final catColor = CategoryVisuals.color(category.id);
    final bg = isSelected
        ? catColor
        : (isDark ? const Color(0xFF282346) : const Color(0xFFF1EFFB));
    final textColor = isSelected
        ? Colors.white
        : (isDark
            ? AppColorTokens.bloomDarkTextSecondary
            : const Color(0xFF5B5580));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(17),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CategoryVisuals.icon(category.icon),
              size: 16,
              color: textColor,
            ),
            const SizedBox(width: 6),
            Text(
              category.name,
              style: AppTheme.bloomDisplay(
                13,
                FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreCategoryChip extends StatelessWidget {
  const _MoreCategoryChip({
    required this.isDark,
    required this.onTap,
  });

  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF282346) : const Color(0xFFF1EFFB);
    final textColor = isDark
        ? AppColorTokens.bloomDarkTextSecondary
        : const Color(0xFF5B5580);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(17),
        ),
        alignment: Alignment.center,
        child: Text(
          'More…',
          style: AppTheme.bloomDisplay(
            13,
            FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

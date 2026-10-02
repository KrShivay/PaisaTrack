import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/category_visuals.dart';
import '../../core/undo/undo_controller.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../../core/widgets/category_picker_sheet.dart';
import '../../data/confidence_payload.dart';
import '../../data/db/database.dart' show Category, Transaction;
import '../../data/db/database_provider.dart';
import '../../data/models/normalized_transaction_record.dart'
    show FieldEvidence;
import '../../data/repositories/category_correction.dart';
import '../../data/repositories/sms_disposition_repository.dart';
import '../../intelligence/derived_reads_service.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../enrichment/source_currency_repair_service.dart';
import 'detail/transaction_detail_evidence.dart';
import 'detail/transaction_detail_formatting.dart';
import 'currency_repair_providers.dart';
import 'transaction_correction_controller.dart';
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
  bool _savingParseConfirmation = false;
  bool _savingCurrencyRepair = false;
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

  Future<void> _confirmParsedDetails() async {
    if (_savingParseConfirmation) return;
    setState(() => _savingParseConfirmation = true);
    try {
      final database = await ref.read(appDatabaseProvider.future);
      final repository = ref.read(transactionRepositoryProvider(database));
      final recorded = await repository.confirmParse(txnId: widget.txnId);
      if (recorded) {
        ref.read(undoControllerProvider.notifier).pushUndo(
              UndoToken(
                id: 'parse_confirm_${widget.txnId}',
                message: 'Parsed details confirmed',
                undoAction: () async {
                  await repository.undoParseConfirmation(
                    txnId: widget.txnId,
                  );
                },
              ),
            );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not confirm parsed details.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingParseConfirmation = false);
    }
  }

  Future<void> _confirmCurrencyRepair(
    SourceCurrencyRepairPreview preview,
  ) async {
    if (_savingCurrencyRepair) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Use INR from the original SMS?'),
        content: Text(
          'The retained message shows “${preview.currencyToken}” beside '
          'this transaction’s ${(preview.amountPaise / 100).toStringAsFixed(2)}. '
          'This changes only its currency label to INR (₹).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apply INR'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _savingCurrencyRepair = true);
    try {
      final database = await ref.read(appDatabaseProvider.future);
      final repair = SourceCurrencyRepairService(database);
      final applied = await repair.apply(preview);
      if (!applied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('The source changed; currency was not updated.'),
            ),
          );
        }
        return;
      }

      ref.read(undoControllerProvider.notifier).pushUndo(
            UndoToken(
              id: 'currency_repair_${widget.txnId}',
              message: 'Currency set to INR',
              undoAction: () async {
                await repair.undo(preview);
                ref.invalidate(
                  sourceCurrencyRepairPreviewProvider(widget.txnId),
                );
                ref.invalidate(transactionDetailProvider(widget.txnId));
              },
            ),
          );
      ref.invalidate(sourceCurrencyRepairPreviewProvider(widget.txnId));
      ref.invalidate(transactionDetailProvider(widget.txnId));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Currency could not be updated.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingCurrencyRepair = false);
    }
  }

  TransactionCorrectionController get _correctionController =>
      TransactionCorrectionController(
        loadDatabase: () => ref.read(appDatabaseProvider.future),
        resolveRepository: (database) =>
            ref.read(transactionRepositoryProvider(database)),
        undoController: ref.read(undoControllerProvider.notifier),
      );

  Future<void> _changeCategory() async {
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

    final scope = await showBloomModalSheet<CorrectionScope>(
      context: context,
      builder: (context) => CategoryScopeSelectionSheet(
        categoryName: chosen.name,
      ),
    );
    if (scope == null || !mounted) return;

    final prevCategory = _categoryId;
    CategoryCorrectionResult? correction;

    setState(() {
      _categoryId = chosen.id;
      _categoryName = chosen.name;
    });

    await _correctionController.apply(
      id: 'cat_detail_${widget.txnId}',
      message: 'Category updated to ${chosen.name}',
      action: (repo) async {
        correction = await repo!.correctCategory(
          txnId: widget.txnId,
          categoryId: chosen.id,
          scope: scope,
          context: 'detail_edit',
        );
      },
      undo: (repo) async {
        final result = correction;
        if (result != null && !await repo!.undoCategoryCorrection(result)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Could not undo: a newer rule now owns this category.',
                ),
              ),
            );
          }
          throw StateError('Category correction is no longer reversible');
        }
        if (mounted) {
          setState(() => _categoryId = prevCategory);
        }
      },
    );
  }

  Future<void> _selectCategoryDirectly(Category chosen) async {
    final prevCategory = _categoryId;
    final prevCategoryName = _categoryName;

    setState(() {
      _categoryId = chosen.id;
      _categoryName = chosen.name;
    });

    try {
      await _correctionController.apply(
        id: 'cat_detail_${widget.txnId}',
        message: 'Category updated to ${chosen.name}',
        action: (repo) async {
          await repo!.correctCategory(
            txnId: widget.txnId,
            categoryId: chosen.id,
            scope: CorrectionScope.thisTransaction,
            context: 'detail_chip_edit',
          );
        },
        undo: (repo) async {
          if (prevCategory != null) {
            await repo!.updateWithFeedback(
              txnId: widget.txnId,
              categoryId: Value(prevCategory),
              context: 'undo_detail',
            );
            if (mounted) {
              setState(() => _categoryId = prevCategory);
            }
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update category: $e')),
      );
      setState(() {
        _categoryId = prevCategory;
        _categoryName = prevCategoryName;
      });
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final detailAsync = ref.watch(transactionDetailProvider(widget.txnId));

    return Scaffold(
      // This screen is only presented in Bloom modal/full-screen sheets; their
      // routes own keyboard insets, so the body must not resize a second time.
      resizeToAvoidBottomInset: false,
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
            final currencyRepair =
                txn.currencyCode == null && txn.currencySymbol == null
                    ? ref.watch(sourceCurrencyRepairPreviewProvider(txn.id))
                    : const AsyncValue.data(null);
            final isDebit = txn.direction == 'debit';
            final currentCatId =
                _categoryId ?? txn.categoryId ?? 'uncategorized';
            final categoryDisplayName =
                _categoryName ?? detail.categoryName ?? 'Uncategorised';
            final displayName =
                detail.merchantName ?? txn.merchantRaw ?? 'Transaction';
            final date =
                DateTime.fromMillisecondsSinceEpoch(txn.ts, isUtc: true);

            final allCategories = ref.watch(categoryListProvider).valueOrNull ??
                const <Category>[];
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

            final suggestedIds = ref
                    .watch(suggestedCategoriesProvider(widget.txnId))
                    .valueOrNull ??
                [];
            final chips =
                chipCategories(currentCat, allCategories, suggestedIds);

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
                              formatDetailDate(date),
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
                    currencyCode: txn.currencyCode,
                    currencySymbol: txn.currencySymbol,
                    size: 44,
                    weight: FontWeight.w600,
                  ),
                  const SizedBox(height: 24),

                  if (currencyRepair.valueOrNull case final preview?) ...[
                    _CurrencyRepairCard(
                      preview: preview,
                      saving: _savingCurrencyRepair,
                      onConfirm: () => _confirmCurrencyRepair(preview),
                    ),
                    const SizedBox(height: 20),
                  ],

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
                          label:
                              'Category, $categoryDisplayName, double tap to change',
                          button: true,
                          child: InkWell(
                            onTap: _changeCategory,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4.0),
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
                                        for (final cat in chips) ...[
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
                  if (exclusionReasonFor(txn) case final reason?) ...[
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
                            color: isDark
                                ? const Color(0xFF60A5FA)
                                : Colors.blue.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              reason,
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
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          runSpacing: 4,
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
                  // WHERE THIS CAME FROM (T-147a & T-147b) - First-class source message section
                  if (txn.smsId != null) ...[
                    _WhereThisCameFromSection(
                      rawSmsBody: detail.rawSmsBody,
                      parseSource: txn.parseSource,
                      parseConfidence: detail.parseConfidence,
                      isNotTransaction: txn.isNotTransaction,
                      onMarkNotTransaction: txn.isNotTransaction
                          ? null
                          : () => _markNotTransaction(txn),
                      isDark: isDark,
                    ),
                    const SizedBox(height: 20),
                  ],

                  if (detail.canConfirmParse) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColorTokens.bloomDarkCard
                            : const Color(0xFFF6F4FE),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? AppColorTokens.bloomDarkOutline
                              : AppColorTokens.bloomChip,
                        ),
                      ),
                      child: detail.isParseConfirmed
                          ? const Text('Parsed details confirmed')
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Does the parsed amount, direction and payee '
                                  'match this message?',
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: _savingParseConfirmation
                                        ? null
                                        : _confirmParsedDetails,
                                    icon: _savingParseConfirmation
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.verified_rounded),
                                    label: const Text(
                                      'Confirm parsed details',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'This records parse feedback only. It does '
                                  'not confirm the transaction or change its '
                                  'category.',
                                  style: AppTheme.bloomDisplay(
                                    12,
                                    FontWeight.w400,
                                    color: isDark
                                        ? AppColorTokens.bloomDarkTextSecondary
                                        : AppColorTokens.inkSecondary,
                                  ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 20),
                  ],

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

  Future<void> _markNotTransaction(Transaction transaction) async {
    final smsId = transaction.smsId;
    if (smsId == null) return;
    final database = await ref.read(appDatabaseProvider.future);
    final dispositions = SmsDispositionRepository(
      database,
      derivedReadsService: await ref.read(derivedReadsServiceProvider.future),
    );
    await dispositions.markNotTransaction(transaction);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Marked as not a transaction.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => dispositions.restore(smsId),
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) =>
      buildEvidenceSpans(rawSmsBody, evidence, isDark, parseConfidence);
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
    return Semantics(
      button: true,
      label: 'Select category ${category.name}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? CategoryVisuals.color(category.id)
                : (isDark ? const Color(0xFF282346) : const Color(0xFFF1EFFB)),
            borderRadius: BorderRadius.circular(17),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CategoryVisuals.icon(category.icon),
                size: 16,
                color: isSelected
                    ? Colors.white
                    : (isDark
                        ? AppColorTokens.bloomDarkTextSecondary
                        : const Color(0xFF5B5580)),
              ),
              const SizedBox(width: 6),
              Text(
                category.name,
                style: AppTheme.bloomDisplay(
                  13,
                  FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : (isDark
                          ? AppColorTokens.bloomDarkTextSecondary
                          : const Color(0xFF5B5580)),
                ),
              ),
            ],
          ),
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

    return Semantics(
      button: true,
      label: 'More categories',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(17),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.more_horiz_rounded,
                size: 16,
                color: textColor,
              ),
              const SizedBox(width: 4),
              Text(
                'More',
                style: AppTheme.bloomDisplay(
                  13,
                  FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WhereThisCameFromSection extends StatelessWidget {
  const _WhereThisCameFromSection({
    required this.rawSmsBody,
    this.parseSource,
    this.parseConfidence,
    required this.isNotTransaction,
    this.onMarkNotTransaction,
    required this.isDark,
  });

  final String? rawSmsBody;
  final String? parseSource;
  final double? parseConfidence;
  final bool isNotTransaction;
  final VoidCallback? onMarkNotTransaction;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF132820) : const Color(0xFFF1FBF6);
    final border = isDark ? const Color(0xFF1B4D3E) : const Color(0xFFC9EEDD);
    final textColor = isDark
        ? AppColorTokens.bloomDarkTextSecondary
        : const Color(0xFF4E7A69);

    final displayBody =
        rawSmsBody ?? 'Original message no longer stored — kept for 30 days';

    final infoLine = parserSourceLabel(parseSource, parseConfidence);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WHERE THIS CAME FROM',
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayBody,
                style: AppTheme.bloomMono(
                  11,
                  FontWeight.w400,
                  color: textColor,
                ).copyWith(height: 1.6),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onMarkNotTransaction,
                  icon: Icon(
                    isNotTransaction ? Icons.check_circle_outline : Icons.block,
                    size: 18,
                  ),
                  label: Text(
                    isNotTransaction
                        ? 'Marked not a transaction'
                        : 'Not a transaction',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E7A56),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.security_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Parsed locally',
                          style: AppTheme.bloomDisplay(
                            11,
                            FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      infoLine,
                      style: AppTheme.bloomMono(
                        11,
                        FontWeight.w500,
                        color: isDark
                            ? AppColorTokens.bloomDarkTextSecondary
                            : AppColorTokens.inkSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CurrencyRepairCard extends StatelessWidget {
  const _CurrencyRepairCard({
    required this.preview,
    required this.saving,
    required this.onConfirm,
  });

  final SourceCurrencyRepairPreview preview;
  final bool saving;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Currency evidence found',
            style: AppTheme.bloomDisplay(
              14,
              FontWeight.w700,
              color: isDark
                  ? AppColorTokens.bloomDarkTextPrimary
                  : AppColorTokens.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'The retained SMS has “${preview.currencyToken}” beside the '
            'matching amount. Preview the change to INR (₹).',
            style: AppTheme.bloomDisplay(
              12,
              FontWeight.w400,
              color: isDark
                  ? AppColorTokens.bloomDarkTextSecondary
                  : AppColorTokens.inkSecondary,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: Tooltip(
              message: 'Preview currency from the retained original SMS',
              child: Semantics(
                label: 'Review INR from original SMS',
                button: true,
                child: OutlinedButton.icon(
                  key: const Key('reviewCurrencyRepair'),
                  onPressed: saving ? null : onConfirm,
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.currency_rupee_rounded),
                  label: Text(saving ? 'Applying INR…' : 'Review INR from SMS'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

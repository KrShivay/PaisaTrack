import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_state_views.dart';
import '../../core/widgets/category_picker_sheet.dart';
import '../../core/widgets/correction_scope_sheet.dart';
import '../../core/widgets/transaction_components.dart';
import '../../data/db/database.dart' show Category, Transaction;
import '../../data/db/database_provider.dart';
import '../../data/models/normalized_transaction_record.dart';
import '../../data/repositories/category_correction.dart';
import '../../data/repositories/transaction_repository.dart';
import 'transactions_providers.dart';

/// Read-and-correct view of a single transaction (T-038).
///
/// Shows every frozen §6.2 field plus status, with a confidence-trail
/// placeholder (full enrichment trail lands in Phase 3). Category and
/// description are editable; category changes use an explicit correction
/// scope while description-only edits use
/// [TransactionRepository.updateWithFeedback].
class TransactionDetailScreen extends ConsumerStatefulWidget {
  const TransactionDetailScreen({super.key, required this.txnId});

  final String txnId;

  @override
  ConsumerState<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState
    extends ConsumerState<TransactionDetailScreen> {
  final _descriptionController = TextEditingController();
  bool _editsSeeded = false;
  String? _categoryId;
  String? _initialCategoryId;
  CorrectionScope _categoryScope = CorrectionScope.thisTransaction;
  String _initialDescription = '';
  bool _saving = false;
  bool _savingParseVerdict = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  /// Seeds the editable fields once from the loaded row, so in-progress
  /// edits are not clobbered by stream re-emissions.
  void _seedEdits(TransactionDetail detail) {
    if (_editsSeeded) return;
    _editsSeeded = true;
    _categoryId = detail.txn.categoryId;
    _initialCategoryId = detail.txn.categoryId;
    _initialDescription = detail.txn.description ?? '';
    _descriptionController.text = _initialDescription;
    _descriptionController.addListener(_handleEdit);
  }

  bool get _isDirty =>
      _categoryId != _initialCategoryId ||
      _descriptionController.text.trim() != _initialDescription.trim();

  void _handleEdit() {
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final database = await ref.read(appDatabaseProvider.future);
      final repository = ref.read(transactionRepositoryProvider(database));
      final description = _descriptionController.text.trim();
      final categoryChanged = _categoryId != _initialCategoryId;
      final descriptionChanged = description != _initialDescription.trim();
      CategoryCorrectionResult? correction;
      final written = categoryChanged
          ? (correction = await repository.correctCategory(
              txnId: widget.txnId,
              categoryId: _categoryId!,
              scope: _categoryScope,
              context: 'detail_edit',
              description: descriptionChanged
                  ? Value(description.isEmpty ? null : description)
                  : const Value.absent(),
            ))
              .feedbackCount
          : await repository.updateWithFeedback(
              txnId: widget.txnId,
              description: Value(description.isEmpty ? null : description),
            );
      if (mounted) {
        setState(() {
          _saving = false;
          if (written > 0) {
            _initialCategoryId = _categoryId;
            _initialDescription = description;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              correction?.ruleCreated == true
                  ? 'Saved. PaisaTrack will remember this.'
                  : correction != null &&
                          correction.affectedTransactionCount > 1
                      ? '${correction.affectedTransactionCount} transactions updated'
                      : written > 0
                          ? 'Saved'
                          : 'No changes to save',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save changes')),
        );
      }
    }
  }

  Future<void> _confirmParse() async {
    setState(() => _savingParseVerdict = true);
    try {
      final database = await ref.read(appDatabaseProvider.future);
      await ref
          .read(transactionRepositoryProvider(database))
          .confirmParse(txnId: widget.txnId);
      if (mounted) {
        setState(() => _savingParseVerdict = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Parse confirmed')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _savingParseVerdict = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not confirm parse')),
        );
      }
    }
  }

  Future<void> _fixParse(Transaction txn) async {
    final correction = await showParseCorrectionSheet(
      context,
      amount: txn.amount,
      direction: txn.direction,
      merchantRaw: txn.merchantRaw,
    );
    if (correction == null || !mounted) return;

    setState(() => _savingParseVerdict = true);
    try {
      final database = await ref.read(appDatabaseProvider.future);
      final written = await ref
          .read(transactionRepositoryProvider(database))
          .updateWithFeedback(
            txnId: widget.txnId,
            amount: Value(correction.amount),
            direction: Value(correction.direction),
            merchantRaw: Value(correction.merchantRaw),
            context: 'parse_confirm',
            recordParseCorrections: true,
          );
      if (mounted) {
        setState(() => _savingParseVerdict = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              written > 0 ? 'Parse correction saved' : 'No parse changes',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _savingParseVerdict = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save parse correction')),
        );
      }
    }
  }

  Future<void> _chooseCategory(
    List<Category> categories,
    Transaction transaction,
  ) async {
    final chosen = await showModalBottomSheet<Category>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => CategoryPickerSheet(
        categories: categories,
        currentCategoryId: _categoryId,
        suggestedCategoryIds: [
          if (_categoryId != null) _categoryId!,
          'transfers',
          'other',
        ],
        explanations: {
          if (_categoryId != null) _categoryId!: 'Current category',
          'transfers': 'Use for self-transfers or excluded movement',
        },
      ),
    );
    if (chosen == null || !mounted) return;
    if (chosen.id == _categoryId) return;
    final hasReusableMatch =
        transaction.counterpartyVpa?.trim().isNotEmpty == true ||
            transaction.merchantRaw?.trim().isNotEmpty == true;
    final scope = await showCorrectionScopeSheet(
      context: context,
      categoryName: chosen.name,
      availableScopes: {
        CorrectionScope.thisTransaction,
        if (hasReusableMatch) ...{
          CorrectionScope.futureMatching,
          CorrectionScope.existingAndFuture,
        },
      },
      initialScope: defaultCorrectionScope(CorrectionContext.oneOffEdit),
    );
    if (scope == null || !mounted) return;
    setState(() {
      _categoryId = chosen.id;
      _categoryScope = scope;
    });
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(transactionDetailProvider(widget.txnId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction'),
        actions: [
          if (_editsSeeded && _isDirty)
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
        ],
      ),
      body: switch (detail) {
        AsyncData(:final value?) => _buildDetail(context, value),
        AsyncData() => const EmptyStateView(
            illustration: AppIllustrations.spendAnalysis,
            title: 'Transaction not found',
            message: 'It may have been deleted.',
          ),
        AsyncError() => const ErrorStateView(
            message: 'Could not load this transaction.',
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _buildDetail(BuildContext context, TransactionDetail detail) {
    _seedEdits(detail);
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final txn = detail.txn;
    final isCredit = txn.direction == 'credit';
    final direction =
        isCredit ? TransactionDirection.credit : TransactionDirection.debit;
    final ts =
        DateTime.fromMillisecondsSinceEpoch(txn.ts, isUtc: true).toLocal();
    final categories = ref.watch(categoryListProvider);
    final merchantName =
        detail.merchantName ?? txn.merchantRaw ?? 'Transaction';
    final categoryName = switch (categories) {
      AsyncData(:final value) => _selectedCategoryName(value),
      _ => 'Uncategorized',
    };

    return ListView(
      padding: AppSpacing.screen,
      children: [
        Text(
          merchantName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TransactionAmount(
          amount: txn.amount,
          direction: direction,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${localizations.formatMediumDate(ts)} · '
          '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(ts))}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          [categoryName, txn.channel.toUpperCase(), txn.accountHint]
              .whereType<String>()
              .where((value) => value.isNotEmpty)
              .join(' · '),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        // Rendered only once categories have loaded, so the current category
        // id is always among the dropdown's items (a stale/unknown id would
        // otherwise trip the dropdown's value assertion).
        switch (categories) {
          AsyncData(:final value) => _CategoryField(
              categoryName: _selectedCategoryName(value),
              onTap: () => _chooseCategory(value, txn),
            ),
          _ => const TextField(
              enabled: false,
              decoration: InputDecoration(labelText: 'Category'),
            ),
        },
        const SizedBox(height: AppSpacing.lg),
        TextFormField(
          controller: _descriptionController,
          decoration: const InputDecoration(labelText: 'Description'),
          textCapitalization: TextCapitalization.sentences,
        ),
        if (detail.isLowTrustParse) ...[
          const SizedBox(height: AppSpacing.lg),
          _ParseConfirmationCard(
            saving: _savingParseVerdict,
            onConfirm: _confirmParse,
            onFix: () => _fixParse(txn),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        _DetailSection(
          title: 'Why this category?',
          initiallyExpanded: true,
          child: Text(
            _categoryExplanation(detail),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        _DetailSection(
          title: 'Transaction details',
          child: Column(
            children: [
              _FieldRow(label: 'Direction', value: txn.direction),
              _FieldRow(label: 'Channel', value: txn.channel),
              _FieldRow(label: 'Account', value: txn.accountHint),
              _FieldRow(
                label: 'Balance after',
                value: txn.balanceAfter == null
                    ? null
                    : formatInr(txn.balanceAfter!),
              ),
              _FieldRow(label: 'Reference', value: txn.refId),
              _FieldRow(
                label: 'Counterparty VPA',
                value: txn.counterpartyVpa,
              ),
              _FieldRow(label: 'SMS source', value: txn.parseSource),
            ],
          ),
        ),
        _DetailSection(
          title: 'Developer details',
          child: Column(
            children: [
              _FieldRow(label: 'Parse source', value: txn.parseSource),
              _FieldRow(
                label: 'Parse confidence',
                value: detail.parseConfidence?.toStringAsFixed(2),
              ),
              _FieldRow(
                label: 'Merchant value',
                value: detail.confidenceTrail.merchant?.value?.toString(),
              ),
              _FieldRow(
                label: 'Merchant source',
                value: detail.confidenceTrail.merchant?.source,
              ),
              _FieldRow(
                label: 'Merchant confidence',
                value: detail.confidenceTrail.merchant?.confidence
                    ?.toStringAsFixed(2),
              ),
              _FieldRow(
                label: 'Category source',
                value: detail.confidenceTrail.category?.source,
              ),
              _FieldRow(
                label: 'Category confidence',
                value: detail.confidenceTrail.category?.confidence
                    ?.toStringAsFixed(2),
              ),
              _FieldRow(
                label: 'Category rule',
                value: detail.confidenceTrail.category?.ruleId,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _selectedCategoryName(List<Category> categories) {
    for (final category in categories) {
      if (category.id == _categoryId) return category.name;
    }
    return 'Uncategorized';
  }

  String _categoryExplanation(TransactionDetail detail) {
    final source = detail.confidenceTrail.category?.source?.toLowerCase();
    if (source?.contains('rule') ?? false) {
      return 'Suggested from your rule for this merchant.';
    }
    if (source?.contains('feedback') ?? false) {
      return 'Previously used for similar transactions.';
    }
    if (source?.contains('seed') ?? false) {
      return 'Suggested from PaisaTrack’s category mapping.';
    }
    return detail.txn.categoryId == null
        ? 'Choose a category to help organise this transaction.'
        : 'This category needs your confirmation when it looks incorrect.';
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
  });

  final String title;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
      initiallyExpanded: initiallyExpanded,
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      children: [Align(alignment: Alignment.centerLeft, child: child)],
    );
  }
}

class _CategoryField extends StatelessWidget {
  const _CategoryField({
    required this.categoryName,
    required this.onTap,
  });

  final String categoryName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Category, $categoryName',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Category',
            suffixIcon: Icon(Icons.expand_more),
          ),
          child: Text(categoryName),
        ),
      ),
    );
  }
}

/// Compact verdict control shown only when ADR 0005 requires a user check.
class _ParseConfirmationCard extends StatelessWidget {
  const _ParseConfirmationCard({
    required this.saving,
    required this.onConfirm,
    required this.onFix,
  });

  final bool saving;
  final VoidCallback onConfirm;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Parsed correctly?',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Check the amount, direction, and merchant.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                FilledButton(
                  onPressed: saving ? null : onConfirm,
                  child: const Text('Confirm'),
                ),
                OutlinedButton(
                  onPressed: saving ? null : onFix,
                  child: const Text('Fix'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// User-entered replacements for fields extracted from a low-trust parse.
class ParseCorrection {
  const ParseCorrection({
    required this.amount,
    required this.direction,
    required this.merchantRaw,
  });

  final double amount;
  final String direction;
  final String? merchantRaw;
}

/// Shows the shared amount, direction, and merchant correction form.
Future<ParseCorrection?> showParseCorrectionSheet(
  BuildContext context, {
  required double amount,
  required String direction,
  required String? merchantRaw,
}) async {
  final amountController = TextEditingController(text: amount.toString());
  final merchantController = TextEditingController(text: merchantRaw ?? '');
  var selectedDirection = direction;
  try {
    return await showModalBottomSheet<ParseCorrection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screen.left,
            AppSpacing.screen.top,
            AppSpacing.screen.right,
            MediaQuery.viewInsetsOf(context).bottom + AppSpacing.screen.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Fix parsed fields',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount'),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: selectedDirection,
                decoration: const InputDecoration(labelText: 'Direction'),
                items: const [
                  DropdownMenuItem(value: 'debit', child: Text('Spent')),
                  DropdownMenuItem(value: 'credit', child: Text('Received')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => selectedDirection = value);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: merchantController,
                decoration: const InputDecoration(labelText: 'Merchant'),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: () {
                  final amount = double.tryParse(
                    amountController.text.replaceAll(',', '').trim(),
                  );
                  if (amount == null || amount <= 0) return;
                  final merchant = merchantController.text.trim();
                  Navigator.of(context).pop(
                    ParseCorrection(
                      amount: amount,
                      direction: selectedDirection,
                      merchantRaw: merchant.isEmpty ? null : merchant,
                    ),
                  );
                },
                child: const Text('Save parse correction'),
              ),
            ],
          ),
        ),
      ),
    );
  } finally {
    amountController.dispose();
    merchantController.dispose();
  }
}

/// Label/value row for read-only detail fields; null values render as '—'.
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value ?? '—', style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

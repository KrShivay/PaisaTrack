import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/bloom/bloom_sheet_scaffold.dart';
import '../../data/db/database_provider.dart';
import '../../data/repositories/category_correction.dart';
import '../../data/repositories/transaction_repository.dart';

/// Modal sheet for parse corrections (amount, direction, merchant).
class TransactionCorrectionSheet extends ConsumerStatefulWidget {
  const TransactionCorrectionSheet({
    super.key,
    required this.txnId,
    required this.initialAmount,
    required this.initialDirection,
    this.initialMerchant,
  });

  final String txnId;
  final double initialAmount;
  final String initialDirection;
  final String? initialMerchant;

  @override
  ConsumerState<TransactionCorrectionSheet> createState() =>
      _TransactionCorrectionSheetState();
}

class _TransactionCorrectionSheetState
    extends ConsumerState<TransactionCorrectionSheet> {
  late final TextEditingController _amountController;
  late final TextEditingController _merchantController;
  late String _direction;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountController =
        TextEditingController(text: widget.initialAmount.toStringAsFixed(2));
    _merchantController =
        TextEditingController(text: widget.initialMerchant ?? '');
    _direction = widget.initialDirection;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    super.dispose();
  }

  Future<void> _saveCorrection() async {
    final parsedAmount = double.tryParse(_amountController.text.trim());
    if (parsedAmount == null || parsedAmount <= 0) {
      setState(() => _error = 'Please enter a valid positive amount.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final database = await ref.read(appDatabaseProvider.future);
      final repo = ref.read(transactionRepositoryProvider(database));
      await repo.updateWithFeedback(
        txnId: widget.txnId,
        amount: Value(parsedAmount),
        direction: Value(_direction),
        merchantRaw: Value(_merchantController.text.trim()),
        context: 'parse_correction',
        recordParseCorrections: true,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Failed to save correction: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BloomSheetScaffold(
      title: 'Correct Transaction Parse',
      showBack: false,
      showClose: true,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColorTokens.errorDark.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColorTokens.errorDark.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    _error!,
                    style: AppTheme.bloomDisplay(
                      12,
                      FontWeight.w500,
                      color: AppColorTokens.errorDark,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Amount Field
              Text(
                'AMOUNT (₹)',
                style: AppTheme.bloomDisplay(
                  11,
                  FontWeight.w600,
                  color: isDark
                      ? AppColorTokens.bloomDarkTextTertiary
                      : AppColorTokens.inkTertiary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: isDark
                      ? AppColorTokens.bloomDarkCard
                      : AppColorTokens.bloomCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Direction Choice
              Text(
                'DIRECTION',
                style: AppTheme.bloomDisplay(
                  11,
                  FontWeight.w600,
                  color: isDark
                      ? AppColorTokens.bloomDarkTextTertiary
                      : AppColorTokens.inkTertiary,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Expense (Debit)'),
                      selected: _direction == 'debit',
                      onSelected: (selected) {
                        if (selected) setState(() => _direction = 'debit');
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Income (Credit)'),
                      selected: _direction == 'credit',
                      onSelected: (selected) {
                        if (selected) setState(() => _direction = 'credit');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Merchant Field
              Text(
                'MERCHANT / PAYEE NAME',
                style: AppTheme.bloomDisplay(
                  11,
                  FontWeight.w600,
                  color: isDark
                      ? AppColorTokens.bloomDarkTextTertiary
                      : AppColorTokens.inkTertiary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _merchantController,
                decoration: InputDecoration(
                  hintText: 'e.g. Swiggy, Amazon, HDFC Bank',
                  filled: true,
                  fillColor: isDark
                      ? AppColorTokens.bloomDarkCard
                      : AppColorTokens.bloomCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Save Action
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColorTokens.violetPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _saving ? null : _saveCorrection,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save Correction'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scope selection modal sheet for category corrections.
class CategoryScopeSelectionSheet extends StatelessWidget {
  const CategoryScopeSelectionSheet({
    super.key,
    required this.categoryName,
    this.affectedCount = 1,
  });

  final String categoryName;
  final int affectedCount;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BloomSheetScaffold(
      title: 'Correction Scope',
      showBack: false,
      showClose: true,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Apply "$categoryName" to:',
                style: AppTheme.bloomDisplay(
                  14,
                  FontWeight.w500,
                  color: isDark
                      ? AppColorTokens.bloomDarkTextSecondary
                      : AppColorTokens.inkSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: const EdgeInsets.all(12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: isDark
                        ? AppColorTokens.bloomDarkOutline
                        : AppColorTokens.bloomHairline,
                  ),
                ),
                title: Text(
                  'This transaction only',
                  style: AppTheme.bloomDisplay(15, FontWeight.w600),
                ),
                subtitle: Text(
                  'Changes only this single transaction without creating rules.',
                  style: AppTheme.bloomDisplay(12, FontWeight.w400),
                ),
                onTap: () =>
                    Navigator.of(context).pop(CorrectionScope.thisTransaction),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: const EdgeInsets.all(12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: isDark
                        ? AppColorTokens.bloomDarkOutline
                        : AppColorTokens.bloomHairline,
                  ),
                ),
                title: Text(
                  'Matching merchant (past & future)',
                  style: AppTheme.bloomDisplay(15, FontWeight.w600),
                ),
                subtitle: Text(
                  'Updates history ($affectedCount matching) and learns rule for future parses.',
                  style: AppTheme.bloomDisplay(12, FontWeight.w400),
                ),
                onTap: () => Navigator.of(context)
                    .pop(CorrectionScope.existingAndFuture),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: const EdgeInsets.all(12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: isDark
                        ? AppColorTokens.bloomDarkOutline
                        : AppColorTokens.bloomHairline,
                  ),
                ),
                title: Text(
                  'Future transactions only',
                  style: AppTheme.bloomDisplay(15, FontWeight.w600),
                ),
                subtitle: Text(
                  'Learns rule for future transactions without altering past history.',
                  style: AppTheme.bloomDisplay(12, FontWeight.w400),
                ),
                onTap: () =>
                    Navigator.of(context).pop(CorrectionScope.futureMatching),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

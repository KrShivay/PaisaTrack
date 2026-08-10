import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../data/db/database_provider.dart';
import '../../data/models/normalized_transaction_record.dart';
import '../../data/repositories/transaction_repository.dart';
import 'transactions_providers.dart';

/// Manual transaction entry form (T-037).
///
/// Captures amount, direction, category, description, and date; channel is
/// fixed to cash (the case SMS capture can never see). Saves through
/// [TransactionRepository.insertManual] so rows land `parse_source='manual'`,
/// `status='confirmed'` and render identically to parsed rows. Layout uses
/// design-system tokens only (docs/design-system.md).
class ManualEntryScreen extends ConsumerStatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  ConsumerState<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends ConsumerState<ManualEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  TransactionDirection _direction = TransactionDirection.debit;
  String? _categoryId;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final database = await ref.read(appDatabaseProvider.future);
      final repository = ref.read(transactionRepositoryProvider(database));
      final description = _descriptionController.text.trim();
      await repository.insertManual(
        ManualTransactionDraft(
          amount: double.parse(_amountController.text.trim()),
          direction: _direction,
          ts: _date,
          categoryId: _categoryId,
          description: description.isEmpty ? null : description,
        ),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save transaction')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoryListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Add transaction')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: AppSpacing.screen,
          children: [
            SegmentedButton<TransactionDirection>(
              segments: const [
                ButtonSegment(
                  value: TransactionDirection.debit,
                  label: Text('Spent'),
                  icon: Icon(Icons.arrow_upward),
                ),
                ButtonSegment(
                  value: TransactionDirection.credit,
                  label: Text('Received'),
                  icon: Icon(Icons.arrow_downward),
                ),
              ],
              selected: {_direction},
              onSelectionChanged: (selection) =>
                  setState(() => _direction = selection.single),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
              ),
              validator: (value) {
                final parsed = double.tryParse((value ?? '').trim());
                if (parsed == null || parsed <= 0) {
                  return 'Enter an amount greater than zero';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            DropdownButtonFormField<String?>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Uncategorized'),
                ),
                ...switch (categories) {
                  AsyncData(:final value) => value.map(
                      (category) => DropdownMenuItem<String?>(
                        value: category.id,
                        child: Text(category.name),
                      ),
                    ),
                  _ => const <DropdownMenuItem<String?>>[],
                },
              ],
              onChanged: (value) => setState(() => _categoryId = value),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: AppSpacing.lg),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: const Text('Date'),
              subtitle: Text(
                MaterialLocalizations.of(context).formatMediumDate(_date),
              ),
              onTap: _pickDate,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

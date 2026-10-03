import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart' show formatSourceAmount;
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../data/db/database.dart' show Transaction;
import '../../../data/repositories/payment_source_repository.dart';
import 'transaction_detail_formatting.dart';
import 'upi_qr_action.dart';

/// One labelled, copyable stored field of a transaction.
class TransactionDetailRow {
  const TransactionDetailRow(this.label, this.value);

  final String label;
  final String value;
}

/// Stored transaction fields worth reading or copying, in display order.
///
/// Only fields that are present are returned; values are shown exactly as
/// stored (account hints keep their own masking) and nothing is inferred.
List<TransactionDetailRow> transactionDetailRows(
  Transaction txn, {
  required String title,
  String? paymentSourceName,
}) {
  String? present(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  final vpa = present(txn.counterpartyVpa);
  final payee = present(txn.merchantRaw);
  final showPayee = payee != null &&
      payee.toLowerCase() != title.trim().toLowerCase() &&
      payee.toLowerCase() != vpa?.toLowerCase();
  final ref = present(txn.refId);
  final account = present(txn.accountHint);
  final source = present(paymentSourceName);
  final balance = txn.balanceAfter;
  final currency = txn.currencyCode != null
      ? txn.currencyCode!
      : txn.currencySymbol != null
          ? '${txn.currencySymbol} (ISO code unknown)'
          : null;
  final date = DateTime.fromMillisecondsSinceEpoch(txn.ts, isUtc: true);

  return [
    if (vpa != null) TransactionDetailRow('UPI ID / VPA', vpa),
    if (showPayee) TransactionDetailRow('Payee in SMS', payee),
    if (ref != null) TransactionDetailRow('Reference / RRN', ref),
    TransactionDetailRow('Channel', _channelLabel(txn.channel)),
    if (account != null) TransactionDetailRow('Account or card', account),
    if (source != null) TransactionDetailRow('Payment source', source),
    TransactionDetailRow(
      'Direction',
      txn.direction == 'credit' ? 'Credit (money in)' : 'Debit (money out)',
    ),
    TransactionDetailRow('Date and time', formatDetailDate(date)),
    if (balance != null)
      TransactionDetailRow(
        'Balance after',
        formatSourceAmount(
          balance,
          currencyCode: txn.currencyCode,
          currencySymbol: txn.currencySymbol,
        ),
      ),
    if (currency != null) TransactionDetailRow('Currency', currency),
    if (txn.lifecycleState != 'settled')
      TransactionDetailRow('Status', _sentenceCase(txn.lifecycleState)),
    TransactionDetailRow('Parsed by', parserSourceLabel(txn.parseSource, null)),
  ];
}

String _channelLabel(String channel) => switch (channel) {
      'upi' => 'UPI',
      'card' => 'Card',
      'netbanking' => 'Net banking',
      'atm' => 'ATM',
      'wallet' => 'Wallet',
      'cash' => 'Cash',
      'unknown' => 'Not stated in SMS',
      _ => _sentenceCase(channel),
    };

String _sentenceCase(String value) {
  final words = value.replaceAll('_', ' ').trim();
  if (words.isEmpty) return value;
  return words[0].toUpperCase() + words.substring(1);
}

/// Display name of the payment source a transaction is assigned to.
final paymentSourceNameProvider =
    StreamProvider.autoDispose.family<String?, String>((ref, id) async* {
  final repository = await ref.watch(paymentSourceRepositoryProvider.future);
  yield* repository.watchDisplayName(id);
});

/// "Transaction details" card (T-196): UPI ID, reference, channel, account,
/// balance and more, each copyable.
class TransactionDetailsCard extends StatelessWidget {
  const TransactionDetailsCard({
    super.key,
    required this.transaction,
    required this.title,
    this.paymentSourceName,
  });

  final Transaction transaction;
  final String title;
  final String? paymentSourceName;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rows = transactionDetailRows(
      transaction,
      title: title,
      paymentSourceName: paymentSourceName,
    );
    final labelColor = isDark
        ? AppColorTokens.bloomDarkTextTertiary
        : AppColorTokens.inkTertiary;
    final valueColor =
        isDark ? AppColorTokens.bloomDarkTextPrimary : AppColorTokens.ink;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 4, 8),
      decoration: BoxDecoration(
        color: isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TRANSACTION DETAILS',
            style: AppTheme.bloomDisplay(
              10,
              FontWeight.w600,
              letterSpacing: 0.1,
              color: labelColor,
            ),
          ),
          const SizedBox(height: 4),
          for (final row in rows)
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: '${row.label}: ${row.value}',
                    excludeSemantics: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.label,
                            style: AppTheme.bloomDisplay(
                              11,
                              FontWeight.w500,
                              color: labelColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            row.value,
                            style: AppTheme.bloomDisplay(
                              14,
                              FontWeight.w600,
                              color: valueColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Copy ${row.label}',
                      icon:
                          Icon(Icons.copy_rounded, size: 18, color: labelColor),
                      onPressed: () => _copy(context, row),
                    ),
                    if (row.label == 'UPI ID / VPA')
                      UpiQrAction(
                        counterpartyVpa: transaction.counterpartyVpa,
                        transactionTitle: title,
                      ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, TransactionDetailRow row) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: row.value));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Copied ${row.label}')));
  }
}

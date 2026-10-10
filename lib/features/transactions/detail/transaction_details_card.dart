import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart' show formatSourceAmount;
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../data/db/database.dart' show Transaction;
import '../../../data/repositories/payment_source_repository.dart';
import 'detail_clipboard.dart';
import 'transaction_detail_formatting.dart';
import 'upi_qr_action.dart';

/// One labelled stored field of a transaction. Only the curated identifiers
/// (UPI ID, account/card, reference, amount, date and time) are [copyable].
class TransactionDetailRow {
  const TransactionDetailRow(this.label, this.value, {this.copyable = false});

  final String label;
  final String value;
  final bool copyable;
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
    if (vpa != null) TransactionDetailRow('UPI ID / VPA', vpa, copyable: true),
    if (showPayee) TransactionDetailRow('Payee in SMS', payee),
    if (ref != null)
      TransactionDetailRow('Reference / RRN', ref, copyable: true),
    TransactionDetailRow('Channel', _channelLabel(txn.channel)),
    if (account != null)
      TransactionDetailRow('Account or card', account, copyable: true),
    if (source != null) TransactionDetailRow('Payment source', source),
    TransactionDetailRow(
      'Direction',
      txn.direction == 'credit' ? 'Credit (money in)' : 'Debit (money out)',
    ),
    TransactionDetailRow(
      'Amount',
      formatSourceAmount(
        txn.amount,
        currencyCode: txn.currencyCode,
        currencySymbol: txn.currencySymbol,
      ),
      copyable: true,
    ),
    TransactionDetailRow(
      'Date and time',
      formatDetailDate(date),
      copyable: true,
    ),
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

/// "Transaction details" card (T-196): stored fields, with copy actions only
/// on the curated identifiers. An optional [footer] hosts related controls.
class TransactionDetailsCard extends StatelessWidget {
  const TransactionDetailsCard({
    super.key,
    required this.transaction,
    required this.title,
    this.paymentSourceName,
    this.footer,
  });

  final Transaction transaction;
  final String title;
  final String? paymentSourceName;
  final Widget? footer;

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
                    if (row.copyable)
                      IconButton(
                        tooltip: 'Copy ${row.label}',
                        icon: Icon(
                          Icons.copy_rounded,
                          size: 18,
                          color: labelColor,
                        ),
                        onPressed: () => copyDetailValue(
                          context,
                          text: row.value,
                          label: row.label,
                        ),
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
          if (footer != null)
            Padding(
              padding: const EdgeInsets.only(right: 12, top: 4, bottom: 8),
              child: footer,
            ),
        ],
      ),
    );
  }
}

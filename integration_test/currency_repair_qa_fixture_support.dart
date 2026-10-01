import 'dart:convert';

const currencyRepairQaSourceId = 't193_currency_repair_qa_source';
const currencyRepairQaTransactionId = 't193_currency_repair_qa_transaction';
const currencyRepairQaAmount = 1234.50;
const currencyRepairQaAmountText = 'Rs.1,234.50';
const currencyRepairQaBody =
    'Rs.1,234.50 debited from A/c XX4242 ... Synthetic Currency QA';

String currencyRepairQaEvidenceJson() {
  final start = currencyRepairQaBody.indexOf(currencyRepairQaAmountText);
  return jsonEncode([
    {
      'field': 'amount',
      'start': start,
      'end': start + currencyRepairQaAmountText.length,
      'verbatim': currencyRepairQaAmountText,
      'extractor': 'generic_regex',
    },
  ]);
}

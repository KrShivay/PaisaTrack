import '../data/models/normalized_transaction_record.dart';
import '../data/models/raw_sms.dart';
import 'template_engine/field_normalizer.dart';

/// Conservative, on-device fallback for transactional SMS without a template.
///
/// A record is returned only when direction, amount, and a bank-context signal
/// agree. This deliberately favors reviewable misses over false transactions.
class GenericTransactionParser {
  const GenericTransactionParser({
    FieldNormalizer fieldNormalizer = const FieldNormalizer(),
  }) : _fieldNormalizer = fieldNormalizer;

  final FieldNormalizer _fieldNormalizer;

  static final RegExp _amount = RegExp(
    r'(?:INR|Rs\.?|₹)[.\s]*([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );
  static final RegExp _account = RegExp(
    r'(?:a/c|ac|acct|account)\s*(?:no\.?\s*)?[Xx*\d]*?(\d{3,6})(?=\D|$)',
    caseSensitive: false,
  );
  static final RegExp _vpa = RegExp(r'([a-zA-Z0-9._-]+@[a-zA-Z]{2,})');
  static final RegExp _balance = RegExp(
    r'(?:Avl(?:\.|bl)?\s*Bal|Balance|Bal)[:\s]*(?:INR|Rs\.?|₹)?\s*[\d,]+(?:\.\d{1,2})?',
    caseSensitive: false,
  );
  static final RegExp _ref = RegExp(
    r'(?:Ref(?:\s*No)?|UTR|txn(?:\s*id)?)[:\s#]*([A-Za-z0-9]{6,})',
    caseSensitive: false,
  );
  static final RegExp _merchant = RegExp(
    r'\b(?:at|to|from|towards)\s+(.{1,40}?)(?=\s+(?:on|ref)\b|[.,]|$)',
    caseSensitive: false,
  );
  static final RegExp _hardReject = RegExp(
    r'\b(?:otp|will be debited|will be credited|is due|due on|requested|declined|failed|unsuccessful|cashback|interest credit|against reversal|received from account|statement)\b',
    caseSensitive: false,
  );

  /// Parses [sms] only when its transaction signals meet the fallback guard.
  NormalizedTransactionRecord? parse(RawSms sms) {
    final body = sms.body;
    if (_hardReject.hasMatch(body)) return null;

    final direction = _direction(body);
    if (direction == null) return null;
    final balanceRanges = _balance
        .allMatches(body)
        .map((match) => (match.start, match.end))
        .toList(growable: false);
    final amounts = _amount.allMatches(body).where((match) {
      final isBalance = balanceRanges.any(
        (range) => match.start >= range.$1 && match.end <= range.$2,
      );
      final isLimit = RegExp(
        r'(?:avl\.?\s*)?limit[:\s]*$',
        caseSensitive: false,
      ).hasMatch(body.substring(0, match.start));
      return !isBalance && !isLimit;
    }).toList();
    if (amounts.isEmpty) return null;

    final amountMatch = _nearest(amounts, direction.index);
    final amount = _parseAmount(amountMatch.group(1));
    if (amount == null) return null;

    final account = _account.firstMatch(body)?.group(1);
    final channel = _channel(body);
    final vpa = _vpa.firstMatch(body)?.group(1);
    if (account == null &&
        channel == TransactionChannel.unknown &&
        vpa == null) {
      return null;
    }

    final merchant = _merchant.firstMatch(body)?.group(1)?.trim();
    return NormalizedTransactionRecord(
      amount: amount,
      direction: direction.value,
      channel: channel,
      merchantRaw: merchant == null || merchant.isEmpty ? null : merchant,
      counterpartyVpa: vpa,
      accountHint: account == null ? null : 'xx$account',
      balanceAfter: _balanceAmount(body),
      refId: _ref.firstMatch(body)?.group(1),
      ts: sms.receivedAt,
      parseSource: ParseSource.generic,
      parseConfidence:
          amounts.length == 1 && merchant != null && merchant.isNotEmpty
              ? 0.6
              : 0.5,
    );
  }

  ({TransactionDirection value, int index})? _direction(String body) {
    for (final entry in <({TransactionDirection value, RegExp pattern})>[
      (
        value: TransactionDirection.debit,
        pattern: RegExp(
          r'\bdebited\b|\bspent\b|\bwithdrawn\b|\bpaid\b|\bsent\b|\bdr\b|\bpurchase of\b|\btxn of\b.*\bat\b',
          caseSensitive: false,
        ),
      ),
      (
        value: TransactionDirection.credit,
        pattern: RegExp(
          r'\bcredited\b|\breceived\b|\bdeposited\b|\brefund\b|\breversal\b|\bcr\b',
          caseSensitive: false,
        ),
      ),
    ]) {
      final match = entry.pattern.firstMatch(body);
      if (match != null) return (value: entry.value, index: match.start);
    }
    return null;
  }

  RegExpMatch _nearest(List<RegExpMatch> matches, int index) {
    return matches.reduce((nearest, candidate) {
      final nearestDistance = (nearest.start - index).abs();
      final candidateDistance = (candidate.start - index).abs();
      return candidateDistance < nearestDistance ? candidate : nearest;
    });
  }

  double? _parseAmount(String? value) {
    try {
      return _fieldNormalizer.parseAmount(value);
    } on FormatException {
      return null;
    }
  }

  TransactionChannel _channel(String body) {
    if (RegExp(r'\bUPI\b', caseSensitive: false).hasMatch(body)) {
      return TransactionChannel.upi;
    }
    if (RegExp(r'\bIMPS\b|\bNEFT\b|\bRTGS\b', caseSensitive: false)
        .hasMatch(body)) {
      return TransactionChannel.netbanking;
    }
    if (RegExp(r'\bATM\b|\bcash\b', caseSensitive: false).hasMatch(body)) {
      return TransactionChannel.atm;
    }
    if (RegExp(r'\bPOS\b|\bcard\b', caseSensitive: false).hasMatch(body)) {
      return TransactionChannel.card;
    }
    return TransactionChannel.unknown;
  }

  double? _balanceAmount(String body) {
    final match = _balance.firstMatch(body);
    if (match == null) return null;
    final amount = _amount.firstMatch(match.group(0)!);
    return amount == null ? null : _parseAmount(amount.group(1));
  }
}

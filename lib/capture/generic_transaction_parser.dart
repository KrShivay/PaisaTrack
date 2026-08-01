import '../core/constants.dart';
import '../data/models/normalized_transaction_record.dart';
import '../data/models/raw_sms.dart';
import 'template_engine/field_normalizer.dart';

/// Reason the generic fallback declined to emit a record.
///
/// Mirrors the ordered guard checks in [GenericTransactionParser.parse] so the
/// unparsed dev screen can explain a miss without a schema change (T-070).
enum GenericParseRejection {
  /// Body matched a hard-reject term (OTP, promo, "will be debited", ...).
  hardRejectTerm,

  /// No debit/credit direction keyword was found.
  noDirection,

  /// No usable (non-balance, non-limit) transaction amount was found.
  noAmount,

  /// No account tail, known channel, or VPA to anchor the transaction.
  noContextSignal,
}

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
  static final RegExp _vpa = RegExp(
    r'(?<![a-zA-Z0-9._%+-])([a-zA-Z0-9][a-zA-Z0-9._-]*@[a-zA-Z][a-zA-Z0-9-]+)(?![a-zA-Z0-9.-])',
  );
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
  static final RegExp _salary = RegExp(r'\bsalary\b', caseSensitive: false);
  static final RegExp _hardReject = RegExp(
    r'\b(?:otp|one time password|verification code|cashback offer|pre-approved|apply now|discount coupon|limited period offer|is due|due on|payment due|bill due|minimum amount due|statement|statement.*generated|e-statement|monthly statement|account statement|available balance|bal in a/c|clear balance|current balance|ac bal)\b',
    caseSensitive: false,
  );

  /// Parses [sms] only when its transaction signals meet the fallback guard.
  NormalizedTransactionRecord? parse(RawSms sms) => _evaluate(sms).record;

  /// Explains why the fallback guard rejected [sms], or null when it parses.
  ///
  /// Shares [_evaluate] with [parse] so the reported reason can never drift
  /// from the guard that actually made the decision.
  GenericParseRejection? rejectionReason(RawSms sms) =>
      _evaluate(sms).rejection;

  /// Runs the guard once, yielding either the parsed record or the reason the
  /// guard stopped. Exactly one field is non-null.
  ({NormalizedTransactionRecord? record, GenericParseRejection? rejection})
      _evaluate(RawSms sms) {
    final body = sms.body;
    if (_hardReject.hasMatch(body)) {
      return (record: null, rejection: GenericParseRejection.hardRejectTerm);
    }

    final direction = _direction(body);
    if (direction == null) {
      return (record: null, rejection: GenericParseRejection.noDirection);
    }
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
    if (amounts.isEmpty) {
      return (record: null, rejection: GenericParseRejection.noAmount);
    }

    final amountMatch = _nearest(amounts, direction.index);
    final amount = _parseAmount(amountMatch.group(1));
    if (amount == null) {
      return (record: null, rejection: GenericParseRejection.noAmount);
    }

    final account = _account.firstMatch(body)?.group(1);
    final channel = _channel(body);
    final vpa = _vpa.firstMatch(body)?.group(1);
    if (account == null &&
        channel == TransactionChannel.unknown &&
        vpa == null) {
      return (record: null, rejection: GenericParseRejection.noContextSignal);
    }

    final merchant = _salary.hasMatch(body)
        ? 'Salary'
        : _merchant.firstMatch(body)?.group(1)?.trim();
    final evidence = <FieldEvidence>[
      FieldEvidence(
        field: 'amount',
        start: amountMatch.start,
        end: amountMatch.end,
        verbatim: body.substring(amountMatch.start, amountMatch.end),
        extractor: 'generic_regex',
      ),
      FieldEvidence(
        field: 'direction',
        start: direction.start,
        end: direction.end,
        verbatim: direction.verbatim,
        extractor: 'generic_regex',
      ),
      FieldEvidence(
        field: 'ts',
        start: 0,
        end: body.length,
        verbatim: body,
        extractor: 'generic_regex',
      ),
    ];

    return (
      record: NormalizedTransactionRecord(
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
                ? AppConstants.genericHighParseConfidence
                : AppConstants.genericLowParseConfidence,
        evidence: evidence,
      ),
      rejection: null,
    );
  }

  ({
    TransactionDirection value,
    int index,
    int start,
    int end,
    String verbatim
  })? _direction(String body) {
    ({
      TransactionDirection value,
      int index,
      int start,
      int end,
      String verbatim
    })? earliest;

    for (final entry in <({TransactionDirection value, RegExp pattern})>[
      (
        value: TransactionDirection.debit,
        pattern: RegExp(
          r'\bdebited\b|\bspent\b|\bwithdrawn\b|\bpaid\b|\bsent\b|\bdr\b|\bpurchase of\b|\bdeclined\b|\bfailed\b|\btxn of\b.*\bat\b',
          caseSensitive: false,
        ),
      ),
      (
        value: TransactionDirection.credit,
        pattern: RegExp(
          r'\bcredited\b|\breceived\b|\bdeposited\b|\brefund\b|\breversal\b|\badded back\b|\bcr\b',
          caseSensitive: false,
        ),
      ),
    ]) {
      final match = entry.pattern.firstMatch(body);
      if (match != null) {
        if (earliest == null || match.start < earliest.start) {
          earliest = (
            value: entry.value,
            index: match.start,
            start: match.start,
            end: match.end,
            verbatim: body.substring(match.start, match.end),
          );
        }
      }
    }

    return earliest;
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

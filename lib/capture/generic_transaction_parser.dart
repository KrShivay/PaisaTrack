import '../core/constants.dart';
import '../core/financial_calendar.dart';
import '../data/models/normalized_transaction_record.dart';
import '../data/models/source_currency.dart';
import '../data/models/raw_sms.dart';
import 'template_engine/field_normalizer.dart';

/// Reason the generic fallback declined to emit a record.
///
/// Mirrors the ordered guard checks in [GenericTransactionParser.parse] so the
/// unparsed dev screen can explain a miss without a schema change (T-070).
enum GenericParseRejection {
  /// Body matched a hard-reject term (OTP, promo, failed payment, etc.).
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
    r'(?<currency>USD|US\$|INR|Rs\.?|₹|\$)[.\s]*(?<amount>[\d,]+(?:\.\d{1,2})?)',
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
    r'(?:Avl(?:\.|bl)?\s*Bal|Available\s+Balance|(?:Clear|Current)\s+Balance|Bal\s+in\s+a/c(?:\s*[Xx*\d]{3,6})?|Balance|Bal)(?:\s+(?:is|of))?[:\s]*(?:USD|US\$|INR|Rs\.?|₹|\$)?\s*[\d,]+(?:\.\d{1,2})?',
    caseSensitive: false,
  );
  static final RegExp _ref = RegExp(
    r'(?:Ref(?:\s*No)?|UTR|txn(?:\s*id)?)[:\s#]*([A-Za-z0-9]{6,})',
    caseSensitive: false,
  );
  static final RegExp _transactionDate = RegExp(
    r'\bon\s+(\d{1,2}-[A-Za-z]{3}-\d{2})\b',
    caseSensitive: false,
  );
  static final RegExp _merchant = RegExp(
    r'\b(at|to|from|towards)\s+(.{1,40}?)(?=\s*\((?:UPI\s+)?Ref\b|\s+(?:via|through|from|to|on|ref)\b|[.,;]|$)',
    caseSensitive: false,
  );
  static final RegExp _merchantContext = RegExp(
    r'\b(?:a/c|acct|account)\b|\b(?:upi|imps|neft|rtgs|atm|pos|card)\b',
    caseSensitive: false,
  );
  static final RegExp _salary = RegExp(r'\bsalary\b', caseSensitive: false);
  static final RegExp _hardReject = RegExp(
    r'\b(?:otp|one time password|verification code|cashback offer|pre-approved|apply now|discount coupon|limited period offer|is due|due on|payment due|bill due|minimum amount due|statement|statement.*generated|e-statement|monthly statement|account statement|declined|failed|unsuccessful|could not be processed|reversed|reversal|refund(?:ed)?|credited back|will be (?:debited|credited|charged|transferred|deposited|added to)|(?:expected\s+)?to\s+be\s+(?:debited|credited|charged|transferred|deposited|added to)|(?:scheduled|due)\s+to\s+be\s+(?:debited|credited|charged|transferred|deposited|added to)|(?:payment|transaction|transfer|debit|credit)\b.{0,30}\b(?:scheduled|pending)|\b(?:scheduled|pending)\s+(?:payment|transaction|transfer|debit|credit))\b',
    caseSensitive: false,
  );

  /// Parses [sms] only when its transaction signals meet the fallback guard.
  NormalizedTransactionRecord? parse(
    RawSms sms, {
    FinancialCalendar? calendar,
  }) =>
      _evaluate(sms, calendar: calendar).record;

  /// Explains why the fallback guard rejected [sms], or null when it parses.
  ///
  /// Shares [_evaluate] with [parse] so the reported reason can never drift
  /// from the guard that actually made the decision.
  GenericParseRejection? rejectionReason(RawSms sms) =>
      _evaluate(sms).rejection;

  /// Runs the guard once, yielding either the parsed record or the reason the
  /// guard stopped. Exactly one field is non-null.
  ({NormalizedTransactionRecord? record, GenericParseRejection? rejection})
      _evaluate(RawSms sms, {FinancialCalendar? calendar}) {
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
    final amount = _parseAmount(amountMatch.namedGroup('amount'));
    final currency =
        SourceCurrency.fromToken(amountMatch.namedGroup('currency'));
    if (amount == null) {
      return (record: null, rejection: GenericParseRejection.noAmount);
    }

    final account = _account.firstMatch(body)?.group(1);
    final channel = _channel(body);
    final vpa = _vpa.firstMatch(body)?.group(1);
    RegExpMatch? dateMatch;
    DateTime? transactionDate;
    for (final candidate in _transactionDate.allMatches(body)) {
      if (candidate.start < direction.end ||
          candidate.start - direction.end > 80) {
        continue;
      }
      final gap = body.substring(direction.end, candidate.start);
      if (RegExp(r'[.;\n]').hasMatch(gap)) {
        continue;
      }

      final value = candidate.group(1)!;
      final parsedDate = _fieldNormalizer.parseDateComponents(
        value: value,
        format: 'dd-MMM-yy',
      );
      final day = int.parse(value.split('-').first);
      if (parsedDate == null || parsedDate.day != day) {
        continue;
      }

      dateMatch = candidate;
      transactionDate = _fieldNormalizer.resolveDateOnly(
        date: parsedDate,
        receivedAt: sms.receivedAt,
        calendar: calendar,
      );
      break;
    }
    if (account == null &&
        channel == TransactionChannel.unknown &&
        vpa == null) {
      return (record: null, rejection: GenericParseRejection.noContextSignal);
    }

    final merchantCandidates = _merchant
        .allMatches(body)
        // `from` commonly introduces the source account; it is not enough to
        // establish a counterparty without a separately verified identity.
        .where((match) => match.group(1)!.toLowerCase() != 'from')
        .map((match) => match.group(2)!.trim())
        .where(
          (candidate) =>
              candidate.isNotEmpty && !_merchantContext.hasMatch(candidate),
        )
        .toList(growable: false);
    final merchant = _salary.hasMatch(body)
        ? 'Salary'
        : merchantCandidates.isEmpty
            ? null
            : merchantCandidates.first;
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
        start: dateMatch == null
            ? 0
            : body.indexOf(dateMatch.group(1)!, dateMatch.start),
        end: dateMatch == null
            ? body.length
            : body.indexOf(dateMatch.group(1)!, dateMatch.start) +
                dateMatch.group(1)!.length,
        verbatim: dateMatch?.group(1) ?? body,
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
        ts: transactionDate ?? sms.receivedAt,
        parseSource: ParseSource.generic,
        parseConfidence:
            amounts.length == 1 && merchant != null && merchant.isNotEmpty
                ? AppConstants.genericHighParseConfidence
                : AppConstants.genericLowParseConfidence,
        currencyCode: currency?.code,
        currencySymbol: currency?.symbol,
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
          r'\bdebited\b|\bspent\b|\bwithdrawn\b|\bpaid\b|\bsent\b|\bdr\b|\bpurchased\b|\bcharged\b|\btransferred from\b|\bpurchase of\b|\btxn of\b.*\bat\b',
          caseSensitive: false,
        ),
      ),
      (
        value: TransactionDirection.credit,
        pattern: RegExp(
          r'\bcredited\b|\breceived\b|\bdeposited\b|\badded to\b|\bcr\b',
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
    return amount == null ? null : _parseAmount(amount.namedGroup('amount'));
  }
}

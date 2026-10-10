import 'dart:convert';

import '../data/models/source_currency.dart';
import 'template_engine/field_normalizer.dart';

/// Messages that describe a money movement without being the settled bank
/// transaction itself (ADR 0032). They only annotate transactions; they never
/// create, alter, or delete one.
enum SupportingSmsKind {
  dividend('dividend'),
  rdInstalment('rd_instalment'),
  emiNotice('emi_notice'),
  collectRequest('collect_request');

  const SupportingSmsKind(this.wireName);

  /// Value stored in `sms_transaction_links.kind`.
  final String wireName;

  /// Direction of the linked transaction the message describes.
  String get transactionDirection =>
      this == SupportingSmsKind.dividend ? 'credit' : 'debit';

  static SupportingSmsKind? fromWireName(String? name) {
    for (final kind in values) {
      if (kind.wireName == name) return kind;
    }
    return null;
  }
}

/// Fields extracted from one supporting SMS. Holds message-derived values, so
/// it must never be logged outside the gated logger.
class SupportingSmsInfo {
  const SupportingSmsInfo({
    required this.kind,
    required this.amountPaise,
    required this.currency,
    this.accountSuffixes = const {},
    this.reference,
    this.counterpartyVpa,
    this.counterpartyName,
    this.dueDate,
    this.bodyTokens = const {},
  });

  final SupportingSmsKind kind;

  /// Integer paise of the message's primary amount. Matching never uses
  /// doubles.
  final int amountPaise;
  final SourceCurrency currency;

  /// Trailing 3-4 digits of every account or card number mentioned.
  final Set<String> accountSuffixes;

  /// Upper-cased reference, RRN, or UTR.
  final String? reference;

  /// Lower-cased UPI address named in the message.
  final String? counterpartyVpa;

  /// Display name of the requester or payer when the message names one.
  final String? counterpartyName;

  /// Due date (UTC calendar date) when the message states one.
  final DateTime? dueDate;

  /// Lower-cased significant words of the body, used to match a company name
  /// against a bank narration (dividend advices only).
  final Set<String> bodyTokens;
}

class _KindCues {
  const _KindCues({required this.include, required this.exclude});

  final List<RegExp> include;
  final List<RegExp> exclude;
}

/// Deterministic cue-phrase recognizer for supporting SMS. Cue patterns live
/// in `assets/seed/supporting_sms_cues_in.json`.
class SupportingSmsClassifier {
  SupportingSmsClassifier._(this._cues, this._excludeAll);

  /// Asset holding the cue patterns.
  static const assetPath = 'assets/seed/supporting_sms_cues_in.json';

  factory SupportingSmsClassifier.fromJson(String jsonString) {
    final root = jsonDecode(jsonString) as Map<String, Object?>;
    List<RegExp> compile(Object? raw) => (raw as List<Object?>? ?? const [])
        .whereType<String>()
        .map((pattern) => RegExp(pattern, caseSensitive: false))
        .toList(growable: false);

    final kinds = root['kinds'] as Map<String, Object?>? ?? const {};
    final cues = <SupportingSmsKind, _KindCues>{};
    for (final kind in SupportingSmsKind.values) {
      final entry = kinds[kind.wireName] as Map<String, Object?>?;
      if (entry == null) continue;
      cues[kind] = _KindCues(
        include: compile(entry['include']),
        exclude: compile(entry['exclude']),
      );
    }
    return SupportingSmsClassifier._(cues, compile(root['exclude_all']));
  }

  final Map<SupportingSmsKind, _KindCues> _cues;
  final List<RegExp> _excludeAll;

  /// Recognizes [body] as exactly one supporting kind, or null when it is not
  /// one, matches several kinds, or carries no usable amount.
  SupportingSmsInfo? classify(String body) {
    if (_excludeAll.any((pattern) => pattern.hasMatch(body))) return null;
    SupportingSmsKind? matched;
    for (final entry in _cues.entries) {
      final cues = entry.value;
      if (!cues.include.any((pattern) => pattern.hasMatch(body))) continue;
      if (cues.exclude.any((pattern) => pattern.hasMatch(body))) continue;
      if (matched != null) return null;
      matched = entry.key;
    }
    if (matched == null) return null;

    final amount = _primaryAmount(body);
    if (amount == null) return null;
    return SupportingSmsInfo(
      kind: matched,
      amountPaise: amount.$1,
      currency: amount.$2,
      accountSuffixes: _accountSuffixes(body),
      reference: _reference(body),
      counterpartyVpa: _vpa(body),
      counterpartyName: matched == SupportingSmsKind.collectRequest
          ? _requesterName(body)
          : null,
      dueDate: _dueDate(body),
      bodyTokens: significantTokens(body),
    );
  }

  /// Parses an amount string such as `1,20,000.50` into integer paise, or
  /// null when it is invalid, non-positive, or out of the safe range.
  static int? amountToPaise(String amountText) {
    final double? amount;
    try {
      amount = const FieldNormalizer().parseOptionalAmount(amountText);
    } on FormatException {
      return null;
    }
    if (amount == null || !amount.isFinite || amount <= 0) return null;
    const maxSafePaise = 9007199254740991;
    final paise = amount * 100;
    if (!paise.isFinite || paise > maxSafePaise) return null;
    final rounded = paise.round();
    return rounded > 0 ? rounded : null;
  }

  /// Lower-cased words of at least three letters that are not generic banking
  /// vocabulary. Used for company or requester name overlap.
  static Set<String> significantTokens(String? text) {
    if (text == null) return const {};
    return RegExp(r'[A-Za-z]{3,}')
        .allMatches(text)
        .map((match) => match.group(0)!.toLowerCase())
        .where((token) => !_stopTokens.contains(token))
        .toSet();
  }

  static const _stopTokens = {
    'ltd',
    'the',
    'and',
    'for',
    'you',
    'has',
    'are',
    'not',
    'was',
    'per',
    'via',
    'inr',
    'div',
    'ach',
    'corp',
    'inc',
    'pvt',
    'acct',
    'rrn',
    'utr',
    'txn',
    'rupees',
    'dividend',
    'dividends',
    'credited',
    'credit',
    'debited',
    'debit',
    'amount',
    'account',
    'bank',
    'your',
    'with',
    'from',
    'have',
    'been',
    'that',
    'this',
    'shares',
    'share',
    'equity',
    'warrant',
    'payment',
    'payout',
    'towards',
    'interim',
    'final',
    'limited',
    'company',
    'india',
    'indian',
    'transfer',
    'reference',
    'request',
    'requested',
    'collect',
    'please',
    'thank',
    'thanks',
    'dear',
    'customer',
    'balance',
    'avail',
    'available',
    'upi',
    'imps',
    'neft',
    'rtgs',
    'nach',
    'ecs',
    'date',
    'ref',
    'info',
    'will',
    'paid',
    'received',
    'remitted',
    'processed',
    'instalment',
    'installment',
    'deposit',
    'recurring',
    'loan',
    'emi',
  };

  static final _amountPattern = RegExp(
    r'(Rs\.?|INR|₹|USD|US\$|\$)\s*((?:\d{1,2}(?:,\d{2})*,\d{3}|\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{1,2})?)(?![\d,])',
    caseSensitive: false,
  );
  static final _notPrimaryAmount = RegExp(
    r'(?:\bbal(?:ance)?|\boutstanding|\blimit|\bavl|\bavail\w*|\bo/s|\btotal\s+due)\W{0,6}$',
    caseSensitive: false,
  );

  static (int, SourceCurrency)? _primaryAmount(String body) {
    for (final match in _amountPattern.allMatches(body)) {
      final start = match.start < 30 ? 0 : match.start - 30;
      if (_notPrimaryAmount.hasMatch(body.substring(start, match.start))) {
        continue;
      }
      final currency = SourceCurrency.fromToken(match.group(1));
      final paise = amountToPaise(match.group(2)!);
      if (currency != null && paise != null) return (paise, currency);
    }
    return null;
  }

  static final _accountPattern = RegExp(
    r'(?:a/c|acct?|account|card)\s*\.?\s*(?:no\.?|number|ending(?:\s+(?:with|in))?)?\s*[:#-]?\s*[xX*]*\s*(\d{3,16})\b',
    caseSensitive: false,
  );

  static Set<String> _accountSuffixes(String body) => _accountPattern
      .allMatches(body)
      .map((match) => match.group(1)!)
      .map(
        (digits) =>
            digits.length > 4 ? digits.substring(digits.length - 4) : digits,
      )
      .toSet();

  static final _referencePattern = RegExp(
    r'\b(?:ref(?:erence)?(?:\s*(?:no\.?|number|id))?|rrn|utr(?:\s*no\.?)?|txn\s*id|upi\s*ref(?:erence)?(?:\s*no\.?)?)\s*[:.\-#]?\s*((?=[A-Za-z0-9]*\d)[A-Za-z0-9]{6,22})\b',
    caseSensitive: false,
  );

  static String? _reference(String body) =>
      _referencePattern.firstMatch(body)?.group(1)?.toUpperCase();

  static final _vpaPattern = RegExp(
    r'\b([A-Za-z0-9._-]{2,}@[A-Za-z][A-Za-z0-9.-]{1,})\b',
  );

  static String? _vpa(String body) =>
      _vpaPattern.firstMatch(body)?.group(1)?.toLowerCase();

  static final _requesterPattern = RegExp(
    r'(?:^|[:.\n]\s*)([A-Za-z][A-Za-z0-9 .&\x27-]{1,40}?)\s+(?:has|have)\s+requested\b',
  );
  static final _requestFromPattern = RegExp(
    r'\brequest\s+(?:of|for)\b.{0,30}?\bfrom\s+([A-Za-z0-9][A-Za-z0-9 .&\x27@_-]{1,40}?)(?=\s*(?:\.|,|;|\bvia\b|\bon\b|\bto\b|$))',
    caseSensitive: false,
  );

  static String? _requesterName(String body) {
    final name = _requesterPattern.firstMatch(body)?.group(1) ??
        _requestFromPattern.firstMatch(body)?.group(1);
    final trimmed = name?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static final _namedMonthDue = RegExp(
    r'\b(?:due|on|by|before|dated?)\s+(?:on\s+)?(\d{1,2})[-/ ]([A-Za-z]{3})[A-Za-z]*[-/ ,]*(\d{2}|\d{4})\b',
    caseSensitive: false,
  );
  static final _numericDue = RegExp(
    r'\b(?:due|on|by|before|dated?)\s+(?:on\s+)?(\d{1,2})[-/](\d{1,2})[-/](\d{2}|\d{4})\b',
    caseSensitive: false,
  );
  static const _months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  static DateTime? _dueDate(String body) {
    var match = _namedMonthDue.firstMatch(body);
    int? month;
    if (match != null) {
      month = _months[match.group(2)!.toLowerCase()];
    } else {
      match = _numericDue.firstMatch(body);
      month = int.tryParse(match?.group(2) ?? '');
    }
    if (match == null || month == null) return null;
    final day = int.parse(match.group(1)!);
    var year = int.parse(match.group(3)!);
    if (year < 100) year += 2000;
    final date = DateTime.utc(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }
}

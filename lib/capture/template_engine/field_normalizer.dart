import '../../core/financial_calendar.dart';
import '../../data/models/normalized_transaction_record.dart';
import '../../data/models/source_currency.dart';
import 'template_registry.dart';

/// Converts named regex captures from SMS templates into domain records.
///
/// Templates own pattern recognition; this class owns parsing, normalization,
/// and privacy-preserving formatting such as account hints.
class FieldNormalizer {
  const FieldNormalizer({FinancialCalendar? calendar}) : _calendar = calendar;

  final FinancialCalendar? _calendar;

  FinancialCalendar get calendar => _calendar ?? FinancialCalendar();

  /// Builds a normalized transaction from a template match.
  ///
  /// Missing optional capture groups become `null`. Missing dates fall back to
  /// the SMS receive timestamp because many bank messages omit parseable dates.
  NormalizedTransactionRecord normalizeTemplateMatch({
    required RegExpMatch match,
    required SmsTemplate template,
    required DateTime fallbackTimestamp,
    FinancialCalendar? calendar,
  }) {
    final amountGroup = _namedGroup(match, 'amount');
    final amount = parseAmount(amountGroup);
    final currencyEvidence = _currencyEvidenceBeforeAmount(match, amountGroup);
    final currency = currencyEvidence?.currency;
    final account = _namedGroup(match, 'account');
    final dateGroup = _namedGroup(match, 'date');
    final parsedTs = parseDate(
      value: dateGroup,
      format: template.dateFormat,
      receivedAt: fallbackTimestamp,
      calendar: calendar,
    );

    final input = match.input;
    final evidence = <FieldEvidence>[];

    if (amountGroup != null && amountGroup.isNotEmpty) {
      final start = input.indexOf(amountGroup, match.start);
      if (start != -1 && start <= match.end) {
        evidence.add(
          FieldEvidence(
            field: 'amount',
            start: start,
            end: start + amountGroup.length,
            verbatim: amountGroup,
            extractor: 'template',
          ),
        );
      }
    }
    if (currencyEvidence != null) evidence.add(currencyEvidence.evidence);

    evidence.add(
      FieldEvidence(
        field: 'direction',
        start: match.start,
        end: match.end,
        verbatim: input.substring(match.start, match.end),
        extractor: 'template',
      ),
    );

    if (dateGroup != null && dateGroup.isNotEmpty) {
      final start = input.indexOf(dateGroup, match.start);
      if (start != -1 && start <= match.end) {
        evidence.add(
          FieldEvidence(
            field: 'ts',
            start: start,
            end: start + dateGroup.length,
            verbatim: dateGroup,
            extractor: 'template',
          ),
        );
      } else {
        evidence.add(
          FieldEvidence(
            field: 'ts',
            start: match.start,
            end: match.end,
            verbatim: input.substring(match.start, match.end),
            extractor: 'template',
          ),
        );
      }
    } else {
      evidence.add(
        FieldEvidence(
          field: 'ts',
          start: match.start,
          end: match.end,
          verbatim: input.substring(match.start, match.end),
          extractor: 'template',
        ),
      );
    }

    return NormalizedTransactionRecord(
      amount: amount,
      direction: _parseDirection(template.direction),
      channel: _parseChannel(template.channel),
      merchantRaw: _namedGroup(match, 'merchant'),
      counterpartyVpa: _namedGroup(match, 'vpa'),
      accountHint: account == null ? null : 'xx$account',
      balanceAfter: parseOptionalAmount(_namedGroup(match, 'balance')),
      refId: _namedGroup(match, 'ref'),
      ts: parsedTs,
      parseSource: ParseSource.template,
      parseConfidence: 0.97,
      templateId: template.id,
      templateProvenance: template.provenance.wireName,
      currencyCode: currency?.code,
      currencySymbol: currency?.symbol,
      evidence: evidence,
    );
  }

  ({SourceCurrency currency, FieldEvidence evidence})?
      _currencyEvidenceBeforeAmount(RegExpMatch match, String? amount) {
    if (amount == null || amount.isEmpty) return null;
    var start = match.input.indexOf(amount, match.start);
    while (start >= 0 && start <= match.end) {
      final prefixStart = start > 16 ? start - 16 : 0;
      final prefix = match.input.substring(prefixStart, start);
      final token = RegExp(
        r'(?<![A-Za-z])(?:USD|US\$|INR|Rs\.?|₹|\$)\s*$',
        caseSensitive: false,
      ).firstMatch(prefix);
      final tokenText = token?.group(0)?.trim();
      final currency = SourceCurrency.fromToken(tokenText);
      if (currency != null && token != null && tokenText != null) {
        final tokenStart = prefixStart + token.start;
        return (
          currency: currency,
          evidence: FieldEvidence(
            field: 'currency',
            start: tokenStart,
            end: tokenStart + tokenText.length,
            verbatim: tokenText,
            extractor: 'template',
          ),
        );
      }
      final afterAmount = start + amount.length;
      final suffix = _currencyTokenAfter(
        match.input,
        afterAmount,
        match.end,
      );
      if (suffix != null) {
        final currency = SourceCurrency.fromToken(suffix.verbatim);
        if (currency != null) {
          return (currency: currency, evidence: suffix);
        }
      }
      start = match.input.indexOf(amount, start + 1);
    }
    return null;
  }

  /// Reads currency evidence immediately before an exact amount span.
  /// The local window prevents later balance/limit tokens from labeling it.
  SourceCurrency? currencyAtAmount(String body, int amountStart) {
    final start = amountStart < 0
        ? 0
        : amountStart > body.length
            ? body.length
            : amountStart;
    final prefix = body.substring(start > 16 ? start - 16 : 0, start);
    final token = RegExp(
      r'(?<![A-Za-z])(?:USD|US\$|INR|Rs\.?|₹|\$)\s*$',
      caseSensitive: false,
    ).firstMatch(prefix);
    return SourceCurrency.fromToken(token?.group(0)?.trim());
  }

  ({SourceCurrency currency, FieldEvidence evidence})? currencyEvidenceAtAmount(
    String body,
    int amountStart,
    int amountEnd,
  ) {
    final start = amountStart.clamp(0, body.length);
    final end = amountEnd.clamp(start, body.length);
    final prefixStart = start > 16 ? start - 16 : 0;
    final prefix = body.substring(prefixStart, start);
    final tokenBefore = RegExp(
      r'(?<![A-Za-z])(?:USD|US\$|INR|Rs\.?|₹|\$)\s*$',
      caseSensitive: false,
    ).firstMatch(prefix);
    final beforeText = tokenBefore?.group(0)?.trim();
    final beforeCurrency = SourceCurrency.fromToken(beforeText);
    if (tokenBefore != null && beforeText != null && beforeCurrency != null) {
      final tokenStart = prefixStart + tokenBefore.start;
      return (
        currency: beforeCurrency,
        evidence: FieldEvidence(
          field: 'currency',
          start: tokenStart,
          end: tokenStart + beforeText.length,
          verbatim: beforeText,
          extractor: 'template',
        ),
      );
    }
    final suffix = _currencyTokenAfter(body, end, body.length);
    if (suffix == null) return null;
    final afterCurrency = SourceCurrency.fromToken(suffix.verbatim);
    return afterCurrency == null
        ? null
        : (currency: afterCurrency, evidence: suffix);
  }

  FieldEvidence? _currencyTokenAfter(String body, int amountEnd, int limit) {
    final suffixEnd = (amountEnd + 16).clamp(amountEnd, limit);
    final suffix = body.substring(amountEnd, suffixEnd);
    final token = RegExp(
      r'^\s*(USD|US\$|INR|Rs\.?|₹|\$)(?=\s|$|[.,])',
      caseSensitive: false,
    ).firstMatch(suffix);
    final tokenText = token?.group(1);
    if (token == null || tokenText == null) return null;
    final leadingWhitespace = token.group(0)!.length - tokenText.length;
    final tokenStart = amountEnd + leadingWhitespace;
    return FieldEvidence(
      field: 'currency',
      start: tokenStart,
      end: tokenStart + tokenText.length,
      verbatim: tokenText,
      extractor: 'template',
    );
  }

  /// Parses a positive INR amount from SMS text.
  ///
  /// Throws [FormatException] when the value is missing, invalid, or non-
  /// positive because a transaction record cannot be valid without an amount.
  double parseAmount(String? value) {
    final parsed = parseOptionalAmount(value);
    if (parsed == null || parsed <= 0) {
      throw const FormatException('Amount must be positive');
    }
    return parsed;
  }

  /// Parses an optional INR amount, accepting symbols, `Rs`, `INR`, and commas.
  double? parseOptionalAmount(String? value) {
    if (value == null) {
      return null;
    }

    final normalized = value
        .replaceAll(
          RegExp(r'(?:rs\.?|inr|usd|us\$|₹|\$)', caseSensitive: false),
          '',
        )
        .replaceAll(',', '')
        .trim();
    if (normalized.isEmpty) {
      return null;
    }

    return double.parse(normalized);
  }

  /// Parses supported SMS date formats, otherwise returns [fallback].
  ///
  /// Supports day-first numeric formats (`dd-MM-yy`, `dd/MM/yy`,
  /// `dd-MM-yyyy`, `dd/MM/yyyy`) and the separator-less alpha-month format
  /// used by some bank senders (`ddMMMyy`, e.g. `08Oct23`).
  DateTime parseDate({
    required String? value,
    required String? format,
    required DateTime receivedAt,
    FinancialCalendar? calendar,
  }) {
    final date = parseDateComponents(value: value, format: format);
    if (date == null) return receivedAt;
    return resolveDateOnly(
      date: date,
      receivedAt: receivedAt,
      calendar: calendar,
    );
  }

  /// Parses a date-only value into UTC-backed calendar components.
  ///
  /// This value is not a stored instant. Call [resolveDateOnly] before using
  /// it as a transaction timestamp.
  DateTime? parseDateComponents({
    required String? value,
    required String? format,
  }) {
    if (value == null || format == null) {
      return null;
    }

    if (format == 'ddMMMyy') {
      return _parseAlphaMonthDate(value);
    }

    if (format == 'dd-MMM-yy' || format == 'dd/MMM/yy') {
      final parts = value.split(RegExp(r'[-/]'));
      if (parts.length != 3) {
        return null;
      }
      final month = _monthNames[parts[1].toLowerCase()];
      if (month == null) {
        return null;
      }
      final day = int.tryParse(parts[0]);
      final year = int.tryParse(parts[2]);
      if (day == null || year == null) {
        throw const FormatException('Date components must be numeric');
      }
      return _validatedDate(
        year: _expandTwoDigitYear(year),
        month: month,
        day: day,
      );
    }

    final parts = value.split(RegExp(r'[-/]'));
    if (parts.length != 3) {
      return null;
    }

    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    final third = int.tryParse(parts[2]);
    if (first == null || second == null || third == null) {
      throw const FormatException('Date components must be numeric');
    }

    if (format == 'dd-MM-yy' || format == 'dd/MM/yy') {
      return _validatedDate(
        year: _expandTwoDigitYear(third),
        month: second,
        day: first,
      );
    }
    if (format == 'dd-MM-yyyy' || format == 'dd/MM/yyyy') {
      return _validatedDate(year: third, month: second, day: first);
    }

    return null;
  }

  /// Resolves parsed date-only calendar components against an SMS receive
  /// instant using the configured [FinancialCalendar].
  DateTime resolveDateOnly({
    required DateTime date,
    required DateTime receivedAt,
    FinancialCalendar? calendar,
  }) =>
      (calendar ?? this.calendar)
          .resolveDateOnly(date: date, receivedAt: receivedAt);

  static const Map<String, int> _monthNames = {
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

  /// Parses a separator-less `ddMMMyy` date such as `08Oct23`.
  DateTime? _parseAlphaMonthDate(String value) {
    final match = RegExp(r'^(\d{2})([A-Za-z]{3})(\d{2})$').firstMatch(value);
    if (match == null) {
      return null;
    }

    final month = _monthNames[match.group(2)!.toLowerCase()];
    if (month == null) {
      return null;
    }

    return _validatedDate(
      year: _expandTwoDigitYear(int.parse(match.group(3)!)),
      month: month,
      day: int.parse(match.group(1)!),
    );
  }

  DateTime? _validatedDate({
    required int year,
    required int month,
    required int day,
  }) {
    final date = DateTime.utc(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  String? _namedGroup(RegExpMatch match, String name) {
    try {
      return match.namedGroup(name)?.trim();
    } on ArgumentError {
      return null;
    }
  }

  int _expandTwoDigitYear(int year) {
    return year >= 70 ? 1900 + year : 2000 + year;
  }

  TransactionDirection _parseDirection(String value) {
    return TransactionDirection.values.byName(value);
  }

  TransactionChannel _parseChannel(String value) {
    return TransactionChannel.values.byName(value);
  }
}

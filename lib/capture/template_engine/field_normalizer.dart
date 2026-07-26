import '../../data/models/normalized_transaction_record.dart';
import 'template_registry.dart';

/// Converts named regex captures from SMS templates into domain records.
///
/// Templates own pattern recognition; this class owns parsing, normalization,
/// and privacy-preserving formatting such as account hints.
class FieldNormalizer {
  const FieldNormalizer();

  /// Builds a normalized transaction from a template match.
  ///
  /// Missing optional capture groups become `null`. Missing dates fall back to
  /// the SMS receive timestamp because many bank messages omit parseable dates.
  NormalizedTransactionRecord normalizeTemplateMatch({
    required RegExpMatch match,
    required SmsTemplate template,
    required DateTime fallbackTimestamp,
  }) {
    final amount = parseAmount(_namedGroup(match, 'amount'));
    final account = _namedGroup(match, 'account');

    return NormalizedTransactionRecord(
      amount: amount,
      direction: _parseDirection(template.direction),
      channel: _parseChannel(template.channel),
      merchantRaw: _namedGroup(match, 'merchant'),
      counterpartyVpa: _namedGroup(match, 'vpa'),
      accountHint: account == null ? null : 'xx$account',
      balanceAfter: parseOptionalAmount(_namedGroup(match, 'balance')),
      refId: _namedGroup(match, 'ref'),
      ts: parseDate(
        value: _namedGroup(match, 'date'),
        format: template.dateFormat,
        fallback: fallbackTimestamp,
      ),
      parseSource: ParseSource.template,
      parseConfidence: 0.97,
      templateId: template.id,
      templateProvenance: template.provenance.wireName,
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
        .replaceAll(RegExp(r'(?:rs\.?|inr|₹)', caseSensitive: false), '')
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
    required DateTime fallback,
  }) {
    if (value == null || format == null) {
      return fallback;
    }

    if (format == 'ddMMMyy') {
      return _parseAlphaMonthDate(value) ?? fallback;
    }

    if (format == 'dd-MMM-yy' || format == 'dd/MMM/yy') {
      final parts = value.split(RegExp(r'[-/]'));
      if (parts.length != 3) {
        return fallback;
      }
      final month = _monthNames[parts[1].toLowerCase()];
      if (month == null) {
        return fallback;
      }
      final day = int.tryParse(parts[0]);
      final year = int.tryParse(parts[2]);
      if (day == null || year == null) {
        throw const FormatException('Date components must be numeric');
      }
      return DateTime.utc(_expandTwoDigitYear(year), month, day);
    }

    final parts = value.split(RegExp(r'[-/]'));
    if (parts.length != 3) {
      return fallback;
    }

    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    final third = int.tryParse(parts[2]);
    if (first == null || second == null || third == null) {
      throw const FormatException('Date components must be numeric');
    }

    if (format == 'dd-MM-yy' || format == 'dd/MM/yy') {
      return DateTime.utc(_expandTwoDigitYear(third), second, first);
    }
    if (format == 'dd-MM-yyyy' || format == 'dd/MM/yyyy') {
      return DateTime.utc(third, second, first);
    }

    return fallback;
  }

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

    return DateTime.utc(
      _expandTwoDigitYear(int.parse(match.group(3)!)),
      month,
      int.parse(match.group(1)!),
    );
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

import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/financial_calendar.dart';
import '../data/analytics/financial_eligibility.dart';
import '../data/db/database.dart';
import '../data/models/source_currency.dart';

/// A closed, versioned statement whose facts are tied to recorded transactions.
class TypedClaim {
  const TypedClaim({
    required this.version,
    required this.calculation,
    required this.id,
    required this.scope,
    required this.window,
    required this.metrics,
    required this.evidenceIds,
    required this.evidenceCount,
    required this.truncated,
    required this.inputHash,
    required this.raw,
  });

  final int version;
  final String calculation;
  final String id;
  final Map<String, Object?> scope;
  final Map<String, Object?> window;
  final Map<String, num> metrics;
  final List<String> evidenceIds;
  final int evidenceCount;
  final bool truncated;
  final String inputHash;
  final Map<String, Object?> raw;
}

/// Validates the stored claim envelope and cheap, reproducible arithmetic.
class ClaimValidator {
  const ClaimValidator();

  TypedClaim? parse(Insight row) {
    try {
      final payload = jsonDecode(row.payloadJson);
      if (payload is! Map<String, dynamic>) return null;
      final value = payload['claim'];
      if (value is! Map<String, dynamic>) return null;
      final idsRaw = value['evidence']?['ids'];
      final metricsRaw = value['metrics'];
      final scope = value['scope'];
      final window = value['window'];
      if (value['v'] != 1 ||
          value['calc'] is! String ||
          value['calc'] != '${row.kind}@1' ||
          value['claim_id'] != row.id ||
          value['basis'] != 'observed' ||
          scope is! Map<String, dynamic> ||
          window is! Map<String, dynamic> ||
          metricsRaw is! Map<String, dynamic> ||
          idsRaw is! List ||
          idsRaw.length > 50 ||
          value['input_hash'] is! String) {
        return null;
      }
      if (!_hasOnlyKeys(value, {
        'v',
        'calc',
        'claim_id',
        'basis',
        'scope',
        'window',
        'metrics',
        'evidence',
        'coverage',
        'input_hash',
      })) {
        return null;
      }
      final evidence = value['evidence'];
      final coverage = value['coverage'];
      final currentWindow = window['current'];
      final previousWindow = window['previous'];
      if (evidence is! Map<String, dynamic> ||
          !_hasOnlyKeys(evidence, {'ids', 'total_count', 'truncated'}) ||
          coverage is! Map<String, dynamic> ||
          !_hasOnlyKeys(coverage, {
            'rows',
            'unreviewed',
            'unknown_currency',
            'excluded',
          }) ||
          currentWindow is! List ||
          currentWindow.length != 2 ||
          DateTime.tryParse(currentWindow[0].toString()) == null ||
          DateTime.tryParse(currentWindow[1].toString()) == null ||
          (previousWindow != null &&
              (previousWindow is! List ||
                  previousWindow.length != 2 ||
                  DateTime.tryParse(previousWindow[0].toString()) == null ||
                  DateTime.tryParse(previousWindow[1].toString()) == null)) ||
          window['partial'] is! bool ||
          coverage['rows'] is! int ||
          coverage['unreviewed'] is! int ||
          coverage['unknown_currency'] is! int ||
          coverage['excluded'] is! Map<String, dynamic> ||
          !_hasOnlyKeys(
            coverage['excluded'] as Map<String, dynamic>,
            {
              'not_settled',
              'owned_transfer',
              'analytics_excluded',
              'non_spending',
              'credit',
            },
          ) ||
          (coverage['excluded'] as Map<String, dynamic>).values.any(
                (count) => count is! int,
              ) ||
          evidence['total_count'] is! int ||
          evidence['truncated'] is! bool ||
          !RegExp(r'^[0-9a-f]{16}$').hasMatch(value['input_hash'] as String) ||
          evidence['total_count'] < idsRaw.length ||
          evidence['truncated'] != (evidence['total_count'] > idsRaw.length)) {
        return null;
      }
      final ids = idsRaw.cast<String>();
      if (ids.toSet().length != ids.length ||
          ids.join('\u0000') != ([...ids]..sort()).join('\u0000')) {
        return null;
      }
      final metrics = <String, num>{};
      for (final entry in metricsRaw.entries) {
        if (entry.value is! num || !(entry.value as num).isFinite) {
          return null;
        }
        metrics[entry.key] = entry.value as num;
      }
      if (!_validShape(row.kind, scope, window, metrics) ||
          !_consistent(row.kind, metrics)) {
        return null;
      }
      return TypedClaim(
        version: 1,
        calculation: value['calc'] as String,
        id: row.id,
        scope: Map<String, Object?>.from(scope),
        window: Map<String, Object?>.from(window),
        metrics: metrics,
        evidenceIds: List.unmodifiable(ids),
        evidenceCount: evidence['total_count'] as int,
        truncated: evidence['truncated'] as bool,
        inputHash: value['input_hash'] as String,
        raw: Map<String, Object?>.from(value),
      );
    } on Object {
      return null;
    }
  }

  bool _hasOnlyKeys(Map<String, dynamic> value, Set<String> allowed) =>
      value.keys.toSet().difference(allowed).isEmpty &&
      allowed.difference(value.keys.toSet()).isEmpty;

  bool _validShape(
    String kind,
    Map<String, dynamic> scope,
    Map<String, dynamic> window,
    Map<String, num> metrics,
  ) {
    final shape = switch (kind) {
      'category_delta' => (
          scope: {'category_id', 'currency_code', 'currency_symbol'},
          metrics: {'current_total', 'previous_total', 'delta_fraction'},
          previous: true,
        ),
      'fees_total' => (
          scope: {'category_ids', 'currency_code', 'currency_symbol'},
          metrics: {'total'},
          previous: false,
        ),
      'price_creep' => (
          scope: {'merchant_id', 'currency_code', 'currency_symbol'},
          metrics: {'expected_amount', 'last_amount'},
          previous: false,
        ),
      'duplicate_subscription' => (
          scope: {'merchant_ids', 'currency_code', 'currency_symbol'},
          metrics: {'monthly_total', 'series_count'},
          previous: false,
        ),
      'missed_autopay' => (
          scope: {'merchant_id', 'currency_code', 'currency_symbol'},
          metrics: {'expected_amount'},
          previous: false,
        ),
      _ => null,
    };
    if (shape == null ||
        !_hasOnlyKeys(scope, shape.scope) ||
        !_hasOnlyKeys(metrics, shape.metrics) ||
        !_hasOnlyKeys(window, {'current', 'previous', 'partial'})) {
      return false;
    }
    if (shape.previous != (window['previous'] != null)) return false;
    for (final key in ['currency_code', 'currency_symbol']) {
      if (scope[key] != null && scope[key] is! String) return false;
    }
    if (kind == 'fees_total' &&
        (scope['category_ids'] is! List ||
            (scope['category_ids'] as List).any((id) => id is! String))) {
      return false;
    }
    if (kind == 'duplicate_subscription' &&
        (scope['merchant_ids'] is! List ||
            (scope['merchant_ids'] as List).any((id) => id is! String))) {
      return false;
    }
    return true;
  }

  bool _consistent(String kind, Map<String, num> metrics) {
    if (kind == 'fees_total') return (metrics['total'] ?? -1) >= 0;
    if (kind == 'price_creep') {
      final expected = metrics['expected_amount'];
      final last = metrics['last_amount'];
      return expected != null && last != null && expected > 0 && last > 0;
    }
    if (kind == 'duplicate_subscription') {
      final total = metrics['monthly_total'];
      final count = metrics['series_count'];
      return total != null &&
          total >= 0 &&
          count != null &&
          count > 1 &&
          count == count.roundToDouble();
    }
    if (kind == 'missed_autopay') {
      final expected = metrics['expected_amount'];
      return expected != null && expected > 0;
    }
    if (kind != 'category_delta') return false;
    final current = metrics['current_total'];
    final previous = metrics['previous_total'];
    final delta = metrics['delta_fraction'];
    return current != null &&
        previous != null &&
        delta != null &&
        previous > 0 &&
        (delta - (current - previous) / previous).abs() < 0.000001;
  }

  bool isFresh(
    TypedClaim claim,
    Iterable<Transaction> rows, {
    required FinancialCalendar calendar,
    Map<String, bool> categoryEligibility = const {},
  }) {
    final evidence = ClaimEvidenceScope.select(
      claim,
      rows,
      calendar: calendar,
      categoryEligibility: categoryEligibility,
    );
    return evidence.length == claim.evidenceCount &&
        claim.evidenceIds.join('\u0000') ==
            evidence.take(50).map((row) => row.id).join('\u0000') &&
        claim.inputHash == inputHash(evidence) &&
        (claim.truncated || _matchesEvidence(claim, evidence, calendar));
  }

  bool _matchesEvidence(
    TypedClaim claim,
    List<Transaction> rows,
    FinancialCalendar calendar,
  ) {
    final matchingCurrency = rows;
    if (claim.calculation == 'fees_total@1') {
      final total =
          matchingCurrency.fold<double>(0, (sum, row) => sum + row.amount);
      return _near(total, claim.metrics['total']);
    }
    if (claim.calculation == 'price_creep@1') {
      if (rows.isEmpty) return false;
      final occurrences = [...rows]..sort((a, b) => a.ts.compareTo(b.ts));
      return _near(
            occurrences.first.amount,
            claim.metrics['expected_amount'],
          ) &&
          _near(occurrences.last.amount, claim.metrics['last_amount']);
    }
    if (claim.calculation == 'duplicate_subscription@1') {
      final total = rows.fold<double>(0, (sum, row) => sum + row.amount);
      return rows.length == claim.metrics['series_count'] &&
          _near(total, claim.metrics['monthly_total']);
    }
    if (claim.calculation == 'missed_autopay@1') {
      if (rows.isEmpty) return false;
      final average =
          rows.fold<double>(0, (sum, row) => sum + row.amount) / rows.length;
      return _near(average, claim.metrics['expected_amount']);
    }
    if (claim.calculation != 'category_delta@1') return false;
    final categoryId = claim.scope['category_id'];
    final current = claim.window['current'];
    final previous = claim.window['previous'];
    if (categoryId is! String ||
        current is! List ||
        previous is! List ||
        current.length != 2 ||
        previous.length != 2) {
      return false;
    }
    final currentStart = ClaimEvidenceScope._parseCalendarDate(
      current.first.toString(),
    );
    final currentEnd = ClaimEvidenceScope._parseCalendarDate(
      current.last.toString(),
    );
    final previousStart = ClaimEvidenceScope._parseCalendarDate(
      previous.first.toString(),
    );
    final previousEnd = ClaimEvidenceScope._parseCalendarDate(
      previous.last.toString(),
    );
    if (currentStart == null ||
        currentEnd == null ||
        previousStart == null ||
        previousEnd == null) {
      return false;
    }
    var currentTotal = 0.0;
    var previousTotal = 0.0;
    for (final row in matchingCurrency) {
      if (row.categoryId != categoryId) return false;
      final date = calendar.localDate(
        DateTime.fromMillisecondsSinceEpoch(row.ts, isUtc: true),
      );
      final day = DateTime.utc(date.year, date.month, date.day);
      if (!day.isBefore(currentStart) && !day.isAfter(currentEnd)) {
        currentTotal += row.amount;
      } else if (!day.isBefore(previousStart) && !day.isAfter(previousEnd)) {
        previousTotal += row.amount;
      } else {
        return false;
      }
    }
    return _near(currentTotal, claim.metrics['current_total']) &&
        _near(previousTotal, claim.metrics['previous_total']);
  }

  bool _near(double actual, num? expected) =>
      expected != null && (actual - expected).abs() <= 0.000001;

  /// Stable FNV-1a digest over sorted evidence tuples; no schema/dependency is
  /// needed and edits to any supported input field invalidate the claim.
  String inputHash(Iterable<Transaction> transactions) {
    final rows = transactions.toList()..sort((a, b) => a.id.compareTo(b.id));
    final input = rows.map((row) {
      final fields = [
        row.id,
        row.updatedAt.toUtc().toIso8601String(),
        row.amount.toString(),
        row.categoryId ?? '',
        row.currencyCode ?? '',
        row.currencySymbol ?? '',
        row.ts.toString(),
        row.direction,
        row.lifecycleState,
        row.isDeleted.toString(),
        row.isNotTransaction.toString(),
        row.duplicateOfTxnId ?? '',
        row.ownedTransferId ?? '',
        row.isAnalyticsExcluded.toString(),
        row.merchantId ?? '',
      ];
      return fields.map((part) => '${part.length}:$part').join();
    });
    var high = 0xcbf29ce4;
    var low = 0x84222325;
    for (final byte in utf8.encode(input.join('\n'))) {
      final mixedLow = low ^ byte;
      final product = mixedLow * 0x1b3;
      high = (high * 0x1b3 + (product >> 32) + mixedLow * 0x100) & 0xffffffff;
      low = product & 0xffffffff;
    }
    return '${high.toRadixString(16).padLeft(8, '0')}'
        '${low.toRadixString(16).padLeft(8, '0')}';
  }
}

/// Shared claim-scope query used by the engine's output contract and readers.
abstract final class ClaimEvidenceScope {
  static List<Transaction> select(
    TypedClaim claim,
    Iterable<Transaction> rows, {
    required FinancialCalendar calendar,
    Map<String, bool> categoryEligibility = const {},
    bool eligibleOnly = true,
  }) =>
      rows.where((row) {
        if (eligibleOnly &&
            !FinancialEligibility.includesSpendingDebit(
              row,
              categoryIsSpending: row.categoryId == null ||
                  categoryEligibility[row.categoryId] != false,
            )) {
          return false;
        }
        if (sourceCurrencyBucket(row) !=
            SourceCurrency(
              code: claim.scope['currency_code'] as String?,
              symbol: claim.scope['currency_symbol'] as String?,
            ).bucketKey) {
          return false;
        }
        final categoryId = claim.scope['category_id'];
        if (categoryId is String && row.categoryId != categoryId) return false;
        final merchantId = claim.scope['merchant_id'];
        if (merchantId is String && row.merchantId != merchantId) return false;
        final merchantIds = claim.scope['merchant_ids'];
        if (merchantIds is List && !merchantIds.contains(row.merchantId)) {
          return false;
        }
        final categoryIds = claim.scope['category_ids'];
        if (categoryIds is List && !categoryIds.contains(row.categoryId)) {
          return false;
        }
        final date = calendar.localDate(
          DateTime.fromMillisecondsSinceEpoch(row.ts, isUtc: true),
        );
        final day = DateTime.utc(date.year, date.month, date.day);
        final current = _contains(claim.window['current'], day);
        final previous = _contains(claim.window['previous'], day);
        return current || previous;
      }).toList()
        ..sort((a, b) => a.id.compareTo(b.id));

  static bool _contains(Object? range, DateTime day) {
    if (range is! List || range.length != 2) return false;
    final start = _parseCalendarDate(range[0].toString());
    final end = _parseCalendarDate(range[1].toString());
    return start != null &&
        end != null &&
        !day.isBefore(start) &&
        !day.isAfter(end);
  }

  static DateTime? _parseCalendarDate(String value) {
    if (value.length < 10) return null;
    final date = DateTime.tryParse('${value.substring(0, 10)}T00:00:00Z');
    return date == null ? null : DateTime.utc(date.year, date.month, date.day);
  }
}

/// Revalidates rows with one batched transaction/category read for all claims.
Future<List<Insight>> freshClaims(
  AppDatabase db,
  Iterable<Insight> rows, {
  required FinancialCalendar calendar,
}) async {
  final parsed = <(Insight, TypedClaim)>[];
  const validator = ClaimValidator();
  for (final row in rows) {
    final claim = validator.parse(row);
    if (claim != null && claim.evidenceIds.isNotEmpty) parsed.add((row, claim));
  }
  if (parsed.isEmpty) return const [];
  final ranges = <(DateTime, DateTime)>{};
  for (final (_, claim) in parsed) {
    for (final key in ['current', 'previous']) {
      final window = claim.window[key];
      if (window is! List || window.length != 2) continue;
      final start = ClaimEvidenceScope._parseCalendarDate(
        window.first.toString(),
      );
      final end = ClaimEvidenceScope._parseCalendarDate(
        window.last.toString(),
      );
      if (start == null || end == null) continue;
      final afterEnd = DateTime.utc(end.year, end.month, end.day + 1);
      final range = (
        calendar.day(start.year, start.month, start.day).start,
        calendar.day(afterEnd.year, afterEnd.month, afterEnd.day).start,
      );
      ranges.add(range);
    }
  }
  if (ranges.isEmpty) return const [];
  final results = await Future.wait([
    (db.select(db.transactions)
          ..where(
            (t) => Expression.or([
              for (final (start, end) in ranges)
                t.ts.isBiggerOrEqualValue(start.millisecondsSinceEpoch) &
                    t.ts.isSmallerThanValue(end.millisecondsSinceEpoch),
            ]),
          ))
        .get(),
    db.select(db.categories).get(),
  ]);
  final transactions = results[0] as List<Transaction>;
  final categories = results[1] as List<Category>;
  final eligibility = {for (final row in categories) row.id: row.isSpending};
  final fresh = [
    for (final (row, claim) in parsed)
      if (validator.isFresh(
        claim,
        transactions,
        calendar: calendar,
        categoryEligibility: eligibility,
      ))
        row,
  ];
  final claimsById = {for (final (row, claim) in parsed) row.id: claim};
  fresh.sort((a, b) {
    final aClaim = claimsById[a.id]!;
    final bClaim = claimsById[b.id]!;
    final aEnd = (aClaim.window['current'] as List).last.toString();
    final bEnd = (bClaim.window['current'] as List).last.toString();
    final byWindow = bEnd.compareTo(aEnd);
    if (byWindow != 0) return byWindow;
    final byDelta = (bClaim.metrics['delta_fraction']?.abs() ?? 0)
        .compareTo(aClaim.metrics['delta_fraction']?.abs() ?? 0);
    return byDelta != 0 ? byDelta : a.id.compareTo(b.id);
  });
  return fresh;
}

class ClaimDisplay {
  const ClaimDisplay({required this.title, required this.body});

  final String title;
  final String body;
}

class ClaimDisplayNames {
  const ClaimDisplayNames({required this.categories, required this.merchants});

  final Map<String, String> categories;
  final Map<String, String> merchants;
}

Future<ClaimDisplayNames> loadClaimDisplayNames(AppDatabase db) async {
  final results = await Future.wait([
    db.select(db.categories).get(),
    db.select(db.merchants).get(),
  ]);
  final categories = results[0] as List<Category>;
  final merchants = results[1] as List<Merchant>;
  return ClaimDisplayNames(
    categories: {for (final row in categories) row.id: row.name},
    merchants: {for (final row in merchants) row.id: row.canonicalName},
  );
}

/// Fixed observed-only copy. Payload prose and unknown claim kinds are ignored.
class ClaimRenderer {
  const ClaimRenderer();

  ClaimDisplay? render(
    TypedClaim claim, {
    Map<String, String> categoryNames = const {},
    Map<String, String> merchantNames = const {},
  }) {
    final metrics = claim.metrics;
    final currency = _currency(claim.scope);
    switch (claim.calculation) {
      case 'category_delta@1':
        final category =
            categoryNames[claim.scope['category_id']] ?? 'Category';
        final current = metrics['current_total'];
        final previous = metrics['previous_total'];
        final window = claim.window['current'];
        final previousWindow = claim.window['previous'];
        if (current == null ||
            previous == null ||
            window is! List ||
            previousWindow is! List ||
            window.length != 2 ||
            previousWindow.length != 2) {
          return null;
        }
        return ClaimDisplay(
          title: '$category spending',
          body: 'Spent ${_amount(current, currency)} vs '
              '${_amount(previous, currency)} in the same days last month '
              '(${window[0]}–${window[1]} vs '
              '${previousWindow[0]}–${previousWindow[1]}).',
        );
      case 'fees_total@1':
        final total = metrics['total'];
        if (total == null) return null;
        return ClaimDisplay(
          title: 'Recorded fees',
          body: 'Recorded ${_amount(total, currency)} in fees across '
              '${claim.evidenceCount} transactions this period.',
        );
      case 'price_creep@1':
        final label =
            merchantNames[claim.scope['merchant_id']] ?? 'Recurring payment';
        final expected = metrics['expected_amount'];
        final last = metrics['last_amount'];
        if (expected == null || last == null) return null;
        return ClaimDisplay(
          title: 'Recurring amount changed',
          body: '$label: recorded amount changed from '
              '${_amount(expected, currency)} to ${_amount(last, currency)} '
              'across ${claim.evidenceCount} recorded payments.',
        );
      case 'duplicate_subscription@1':
        final total = metrics['monthly_total'];
        final seriesCount = metrics['series_count'];
        if (total == null || seriesCount is! int) return null;
        return ClaimDisplay(
          title: 'Matching subscriptions',
          body: '$seriesCount recorded payment occurrences total '
              '${_amount(total, currency)} in the evidence window.',
        );
      case 'missed_autopay@1':
        final label =
            merchantNames[claim.scope['merchant_id']] ?? 'Recurring payment';
        final expected = metrics['expected_amount'];
        if (expected == null) return null;
        return ClaimDisplay(
          title: 'Recorded recurring payment history',
          body: '$label averaged ${_amount(expected, currency)} across '
              '${claim.evidenceCount} recorded payments.',
        );
    }
    return null;
  }

  String _currency(Map<String, Object?> scope) {
    final code = scope['currency_code'] as String?;
    if (code != null && code.isNotEmpty) return code;
    final symbol = scope['currency_symbol'] as String?;
    return symbol == null ? 'currency unknown' : '$symbol (currency unknown)';
  }

  String _amount(num amount, String currency) =>
      '$currency ${amount.toStringAsFixed(2)}';
}

String sourceCurrencyBucket(Transaction row) => SourceCurrency(
      code: row.currencyCode,
      symbol: row.currencySymbol,
    ).bucketKey;

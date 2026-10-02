import 'package:drift/drift.dart';

import '../../core/financial_calendar.dart';
import '../../data/analytics/financial_eligibility.dart';
import '../../data/db/database.dart';
import '../../data/models/source_currency.dart';
import '../../enrichment/payee_identity_key.dart';
import '../claim.dart';
import 'assistant_intent.dart';

sealed class AssistantQueryResult {
  const AssistantQueryResult();
}

class TotalQueryResult extends AssistantQueryResult {
  const TotalQueryResult({
    required this.value,
    required this.count,
    required this.label,
    this.currencyBuckets = const [],
  });
  final double? value;
  final int count;
  final String label;
  final List<AssistantCurrencyBucket> currencyBuckets;
}

class AssistantCurrencyBucket {
  const AssistantCurrencyBucket({
    required this.amount,
    required this.count,
    this.currencyCode,
    this.currencySymbol,
  });
  final double amount;
  final int count;
  final String? currencyCode;
  final String? currencySymbol;
  String get key =>
      SourceCurrency(code: currencyCode, symbol: currencySymbol).bucketKey;
}

class BreakdownItem {
  const BreakdownItem(
    this.label,
    this.total, {
    this.currencyCode,
    this.currencySymbol,
  });
  final String label;
  final double total;
  final String? currencyCode;
  final String? currencySymbol;
}

class BreakdownQueryResult extends AssistantQueryResult {
  const BreakdownQueryResult(this.items);
  final List<BreakdownItem> items;
}

class ComparisonQueryResult extends AssistantQueryResult {
  const ComparisonQueryResult({
    required this.current,
    required this.previous,
    this.currencyBuckets = const [],
    this.currentLabel,
    this.previousLabel,
  });
  final double? current;
  final double? previous;
  final List<
      ({
        double current,
        double previous,
        String? currencyCode,
        String? currencySymbol
      })> currencyBuckets;
  final String? currentLabel;
  final String? previousLabel;
  double? get delta =>
      current == null || previous == null ? null : current! - previous!;
  double? get percent => previous == null || previous == 0 || delta == null
      ? null
      : delta! / previous!;
}

class RecurringQueryItem {
  const RecurringQueryItem(
    this.label,
    this.amount,
    this.date, {
    this.currencyCode,
    this.currencySymbol,
  });
  final String label;
  final double amount;
  final DateTime date;
  final String? currencyCode;
  final String? currencySymbol;
}

class RecurringQueryResult extends AssistantQueryResult {
  const RecurringQueryResult(this.items);
  final List<RecurringQueryItem> items;
}

class InsightQueryItem {
  const InsightQueryItem(this.kind, this.text);
  final String kind;
  final String text;
}

class InsightsQueryResult extends AssistantQueryResult {
  const InsightsQueryResult(this.items);
  final List<InsightQueryItem> items;
}

class AssistantClarificationResult extends AssistantQueryResult {
  const AssistantClarificationResult(this.refusal);

  final AssistantRefusal refusal;
}

class _MerchantAmbiguity implements Exception {
  const _MerchantAmbiguity(this.refusal);

  final AssistantRefusal refusal;
}

class _UnmatchedMerchant implements Exception {
  const _UnmatchedMerchant(this.refusal);

  final AssistantRefusal refusal;
}

class _MerchantIdentity {
  const _MerchantIdentity({
    required this.merchantIds,
    required this.nameKeys,
    required this.vpaKeys,
  });

  final Set<String> merchantIds;
  final Set<String> nameKeys;
  final Set<String> vpaKeys;
}

class AssistantQueryEngine {
  AssistantQueryEngine(
    this.database, {
    FinancialCalendar? calendar,
    DateTime Function()? clock,
  })  : calendar = calendar ?? FinancialCalendar(),
        clock = clock ?? DateTime.now;

  final AppDatabase database;
  final FinancialCalendar calendar;
  final DateTime Function() clock;

  Future<AssistantQueryResult> run(AssistantIntent intent) async {
    try {
      return await switch (intent.kind) {
        AssistantIntentKind.periodTotal ||
        AssistantIntentKind.merchantLookup =>
          _total(intent),
        AssistantIntentKind.categoryBreakdown => _breakdown(intent),
        AssistantIntentKind.monthOverMonth => _comparison(intent),
        AssistantIntentKind.upcomingRecurring => _recurring(intent),
        AssistantIntentKind.activeInsights => _insights(intent),
      };
    } on _MerchantAmbiguity catch (ambiguity) {
      return AssistantClarificationResult(ambiguity.refusal);
    } on _UnmatchedMerchant catch (unmatched) {
      return AssistantClarificationResult(unmatched.refusal);
    }
  }

  Future<List<Transaction>> _transactions(
    AssistantIntent intent,
    AssistantTimeRange range,
  ) async {
    final categories = await database.select(database.categories).get();
    final selectedIds = intent.categoryIds.isNotEmpty
        ? intent.categoryIds.toSet()
        : {if (intent.categoryId != null) intent.categoryId!};
    final categoryParents = {
      for (final category in categories) category.id: category.parentId,
    };
    final categoryScope = _descendantCategoryIds(selectedIds, categoryParents);
    final query = database.select(database.transactions)
      ..where((row) {
        final withinRange =
            row.ts.isBiggerOrEqualValue(range.start.millisecondsSinceEpoch) &
                row.ts.isSmallerThanValue(range.end.millisecondsSinceEpoch);
        final eligible = switch (intent.metric) {
          AssistantMetric.spend =>
            FinancialEligibility.spendingDebit(row, database.categories),
          AssistantMetric.income =>
            FinancialEligibility.base(row) & row.direction.equals('credit'),
          AssistantMetric.net => FinancialEligibility.base(row) &
              (row.direction.equals('credit') |
                  FinancialEligibility.spendingDebit(
                    row,
                    database.categories,
                  )),
        };
        Expression<bool> predicate = withinRange & eligible;
        if (categoryScope.isNotEmpty) {
          predicate &= row.categoryId.isIn(categoryScope);
        }
        if (intent.direction != null) {
          predicate &= row.direction.equals(intent.direction!);
        }
        return predicate;
      });
    final rows = await query.get();
    if (intent.merchant == null) return rows;

    final identity = await _resolveMerchantIdentity(intent.merchant!, rows);
    if (identity == null) {
      throw _UnmatchedMerchant(
        AssistantRefusal(
          "I couldn't find a matching payee for '${intent.merchant!.trim()}'. Check the payee name and try again.",
        ),
      );
    }
    return rows.where((row) {
      return (row.merchantId != null &&
              identity.merchantIds.contains(row.merchantId)) ||
          (row.counterpartyVpa != null &&
              identity.vpaKeys
                  .contains(PayeeKey.keyFor(row.counterpartyVpa!))) ||
          (row.merchantRaw != null &&
              _nameKeyForms(row.merchantRaw!).any(identity.nameKeys.contains));
    }).toList(growable: false);
  }

  Future<_MerchantIdentity?> _resolveMerchantIdentity(
    String phrase,
    List<Transaction> eligibleRows,
  ) async {
    final phraseMatcher = WholePhraseMatcher(phrase);
    final normalizedPhrase = PayeeKey.parse(name: phrase).nameKey;
    if (normalizedPhrase.isEmpty) return null;
    final eligibleIds = eligibleRows.map((row) => row.id).toSet();
    if (eligibleIds.isEmpty) return null;
    final eligibleMerchantIds = <String>{
      ...eligibleRows.map((row) => row.merchantId).whereType<String>().toSet(),
    };
    final merchants = await database.select(database.merchants).get();
    final merchantIds = merchants.map((row) => row.id).toSet();
    final surfaces = <String, Set<String>>{
      for (final id in merchantIds) id: <String>{},
    };
    final nameKeys = <String, Set<String>>{
      for (final id in merchantIds) id: <String>{},
    };
    final vpaKeys = <String, Set<String>>{
      for (final id in merchantIds) id: <String>{},
    };
    for (final merchant in merchants) {
      surfaces[merchant.id]!
        ..add(merchant.canonicalName)
        ..add(merchant.userLabel ?? '');
      nameKeys[merchant.id]!
        ..add(PayeeKey.parse(name: merchant.canonicalName).nameKey)
        ..add(PayeeKey.parse(name: merchant.userLabel).nameKey);
    }

    final aliases = await database.select(database.merchantAliases).get();
    final aliasMerchantIds = <String, Set<String>>{};
    for (final alias in aliases) {
      final id = alias.merchantId;
      final value = alias.alias;
      aliasMerchantIds.putIfAbsent(value, () => <String>{}).add(id);
      surfaces[id]!.add(value);
      if (value.contains('@')) {
        vpaKeys[id]!.add(PayeeKey.keyFor(value));
      } else {
        nameKeys[id]!
          ..add(PayeeKey.keyFor(value))
          ..add(PayeeKey.parse(name: value).nameKey);
        // Stored R2 alias keys remove punctuation, including the VPA '@'.
        vpaKeys[id]!.add(value);
      }
    }
    for (final row in eligibleRows) {
      final rowKeys = <String>{
        if (row.counterpartyVpa != null) PayeeKey.keyFor(row.counterpartyVpa!),
        if (row.merchantRaw != null) ..._nameKeyForms(row.merchantRaw!),
      };
      for (final key in rowKeys) {
        eligibleMerchantIds.addAll(aliasMerchantIds[key] ?? const {});
      }
    }
    final eligibleIdList = eligibleIds.toList(growable: false);
    final evidence = <QueryRow>[];
    for (var offset = 0; offset < eligibleIdList.length; offset += 900) {
      final batchIds = eligibleIdList.skip(offset).take(900).toList();
      final placeholders = List.filled(batchIds.length, '?').join(', ');
      final batchEvidence = await database.customSelect(
        '''
SELECT t.merchant_id, e.evidence_type, e.normalized_key, e.display_value
FROM payee_evidence AS e
JOIN transactions AS t ON t.id = e.transaction_id
WHERE t.id IN ($placeholders) AND t.merchant_id IS NOT NULL
''',
        variables: [
          for (final id in batchIds) Variable<String>(id),
        ],
      ).get();
      evidence.addAll(batchEvidence);
    }
    for (final row in evidence) {
      final id = row.read<String>('merchant_id');
      if (!merchantIds.contains(id)) continue;
      final value = row.read<String>('display_value');
      final key = row.read<String>('normalized_key');
      surfaces[id]!.add(value);
      if (row.read<String>('evidence_type') == 'counterparty_vpa') {
        vpaKeys[id]!
          ..add(key)
          ..add(PayeeKey.keyFor(value));
      } else {
        nameKeys[id]!
          ..add(key)
          ..add(PayeeKey.parse(name: value).nameKey);
      }
    }

    final suggestion = _disambiguatedPayee(phrase);
    final matchedIds = <String>{};
    if (suggestion != null) {
      final labelKey = PayeeKey.parse(name: suggestion.label).nameKey;
      final labelMatches = merchants.where((merchant) {
        final id = merchant.id;
        final label = merchant.userLabel ?? merchant.canonicalName;
        return eligibleMerchantIds.contains(id) &&
            PayeeKey.parse(name: label).nameKey == labelKey;
      }).toList()
        ..sort((left, right) => left.id.compareTo(right.id));
      if (suggestion.ordinal != null) {
        if (labelMatches.length == suggestion.total &&
            suggestion.ordinal! <= labelMatches.length) {
          matchedIds.add(labelMatches[suggestion.ordinal! - 1].id);
        }
      } else {
        final handleMerchantIds = <String>{};
        for (final row in eligibleRows) {
          final vpa = row.counterpartyVpa;
          if (vpa == null || _vpaHandleFor(vpa) != suggestion.handle) continue;
          if (row.merchantId != null) handleMerchantIds.add(row.merchantId!);
          handleMerchantIds
              .addAll(aliasMerchantIds[PayeeKey.keyFor(vpa)] ?? const {});
        }
        for (final merchant in labelMatches) {
          if (handleMerchantIds.contains(merchant.id)) {
            matchedIds.add(merchant.id);
          }
        }
      }
    } else {
      for (final id in eligibleMerchantIds) {
        if (!merchantIds.contains(id)) continue;
        if (surfaces[id]!.any(phraseMatcher.matches) ||
            nameKeys[id]!.contains(normalizedPhrase)) {
          matchedIds.add(id);
        }
      }
    }
    if (matchedIds.length > 1) {
      final matchingMerchants = merchants
          .where((merchant) => matchedIds.contains(merchant.id))
          .toList()
        ..sort((left, right) => left.id.compareTo(right.id));
      final labels = matchingMerchants
          .map((merchant) => merchant.userLabel ?? merchant.canonicalName)
          .toList(growable: false);
      final labelCounts = <String, int>{};
      for (final label in labels) {
        labelCounts.update(label, (count) => count + 1, ifAbsent: () => 1);
      }
      final occurrences = <String, int>{};
      final suggestions = [
        for (var index = 0; index < matchingMerchants.length; index++)
          if (labelCounts[labels[index]]! > 1)
            '${labels[index]} (${_vpaHandle(eligibleRows, matchingMerchants[index].id) ?? 'payee ${occurrences.update(labels[index], (count) => count + 1, ifAbsent: () => 1)} of ${labelCounts[labels[index]]}'})'
          else
            labels[index],
      ];
      throw _MerchantAmbiguity(
        AssistantRefusal(
          "I found more than one payee matching '${phrase.trim()}'. Which one did you mean?",
          suggestions: suggestions,
        ),
      );
    }
    if (matchedIds.isNotEmpty) {
      return _MerchantIdentity(
        merchantIds: matchedIds,
        nameKeys: suggestion == null
            ? {for (final id in matchedIds) ...nameKeys[id]!}
            : const {},
        vpaKeys: {for (final id in matchedIds) ...vpaKeys[id]!},
      );
    }

    final rawMatches = eligibleRows
        .where(
          (row) =>
              row.merchantRaw != null &&
              phraseMatcher.matches(row.merchantRaw!),
        )
        .toList(growable: false);
    final rawIdentities = rawMatches
        .map(
          (row) =>
              row.merchantId ?? PayeeKey.parse(name: row.merchantRaw).nameKey,
        )
        .toSet();
    if (rawIdentities.length > 1) {
      throw _MerchantAmbiguity(
        AssistantRefusal(
          "I found more than one payee matching '${phrase.trim()}'. Which one did you mean?",
          suggestions: rawMatches
              .map((row) => row.merchantRaw!)
              .toSet()
              .toList(growable: false),
        ),
      );
    }
    if (rawMatches.isEmpty) return null;
    return _MerchantIdentity(
      merchantIds:
          rawMatches.map((row) => row.merchantId).whereType<String>().toSet(),
      nameKeys: rawMatches
          .expand(
            (row) => [
              PayeeKey.keyFor(row.merchantRaw!),
              PayeeKey.parse(name: row.merchantRaw).nameKey,
            ],
          )
          .toSet(),
      vpaKeys: const {},
    );
  }

  static String? _vpaHandle(List<Transaction> rows, String merchantId) {
    String? vpa;
    for (final row in rows) {
      if (row.merchantId == merchantId && row.counterpartyVpa != null) {
        vpa = row.counterpartyVpa;
        break;
      }
    }
    return vpa == null ? null : _vpaHandleFor(vpa);
  }

  static String? _vpaHandleFor(String vpa) {
    final separator = vpa.lastIndexOf('@');
    return separator < 0 ? null : vpa.substring(separator + 1).toLowerCase();
  }

  static ({String label, String? handle, int? ordinal, int? total})?
      _disambiguatedPayee(String phrase) {
    final match = RegExp(r'^(.+?)\s+\(([^()]+)\)$').firstMatch(phrase.trim());
    if (match == null) return null;
    final label = match.group(1)!.trim();
    final handle = match.group(2)!.trim().toLowerCase();
    final ordinalMatch = RegExp(r'^payee (\d+) of (\d+)$').firstMatch(handle);
    if (ordinalMatch != null) {
      return (
        label: label,
        handle: null,
        ordinal: int.parse(ordinalMatch.group(1)!),
        total: int.parse(ordinalMatch.group(2)!),
      );
    }
    if (label.isEmpty || handle.isEmpty) return null;
    return (label: label, handle: handle, ordinal: null, total: null);
  }

  static Set<String> _nameKeyForms(String value) => {
        PayeeKey.keyFor(value),
        PayeeKey.parse(name: value).nameKey,
      }..remove('');

  Future<TotalQueryResult> _total(AssistantIntent intent) async {
    final rows = await _transactions(intent, intent.range!);
    final selected =
        rows.where((row) => _included(row, intent.metric)).toList();
    final grouped = <String, List<Transaction>>{};
    for (final row in selected) {
      grouped
          .putIfAbsent(
            SourceCurrency(
              code: row.currencyCode,
              symbol: row.currencySymbol,
            ).bucketKey,
            () => [],
          )
          .add(row);
    }
    final buckets = grouped.values.map((bucketRows) {
      final amounts = bucketRows.map((row) => _signed(row, intent.metric));
      final amount = switch (intent.aggregation) {
        AssistantAggregation.count => bucketRows.length.toDouble(),
        AssistantAggregation.average => amounts.isEmpty
            ? 0.0
            : amounts.reduce((a, b) => a + b) / bucketRows.length,
        _ => amounts.fold<double>(0, (sum, value) => sum + value),
      };
      final first = bucketRows.first;
      return AssistantCurrencyBucket(
        amount: amount,
        count: bucketRows.length,
        currencyCode: first.currencyCode,
        currencySymbol: first.currencySymbol,
      );
    }).toList(growable: false);
    final value = intent.aggregation == AssistantAggregation.count
        ? selected.length.toDouble()
        : buckets.length == 1
            ? buckets.single.amount
            : null;
    return TotalQueryResult(
      value: value,
      count: selected.length,
      label: intent.range!.label,
      currencyBuckets: buckets,
    );
  }

  Future<BreakdownQueryResult> _breakdown(AssistantIntent intent) async {
    final rows = await _transactions(intent, intent.range!);
    final categories = {
      for (final row in await database.select(database.categories).get())
        row.id: row.name,
    };
    final totals =
        <(String, String), ({double amount, String? code, String? symbol})>{};
    for (final row in rows.where((row) => _included(row, intent.metric))) {
      final label = categories[row.categoryId] ?? 'Uncategorised';
      final currency =
          SourceCurrency(code: row.currencyCode, symbol: row.currencySymbol)
              .bucketKey;
      final key = (label, currency);
      final prior = totals[key];
      totals[key] = (
        amount: (prior?.amount ?? 0) + _signed(row, intent.metric),
        code: row.currencyCode,
        symbol: row.currencySymbol
      );
    }
    final items = totals.entries.map((e) {
      final label = e.key.$1;
      return BreakdownItem(
        label,
        e.value.amount,
        currencyCode: e.value.code,
        currencySymbol: e.value.symbol,
      );
    }).toList()
      ..sort((a, b) {
        final labelOrder =
            a.label.toLowerCase().compareTo(b.label.toLowerCase());
        if (labelOrder != 0) return labelOrder;
        final aCurrency = SourceCurrency(
          code: a.currencyCode,
          symbol: a.currencySymbol,
        ).bucketKey;
        final bCurrency = SourceCurrency(
          code: b.currencyCode,
          symbol: b.currencySymbol,
        ).bucketKey;
        return aCurrency.compareTo(bCurrency);
      });
    return BreakdownQueryResult(items);
  }

  Future<ComparisonQueryResult> _comparison(AssistantIntent intent) async {
    final currentRange = intent.range!;
    var boundedCurrentRange = currentRange;
    var priorRange = intent.compareRange!;
    var currentLabel = currentRange.label;
    var previousLabel = priorRange.label;
    final now = clock();
    final currentMonth = calendar.monthContaining(now);
    final monthLocal = calendar.localDate(currentMonth.start);
    final fullPrior = calendar.month(monthLocal.year, monthLocal.month - 1);
    final comparingCurrentMonth = currentRange.start == currentMonth.start &&
        currentRange.end == currentMonth.end &&
        priorRange.start == fullPrior.start &&
        priorRange.end == fullPrior.end;
    if (comparingCurrentMonth) {
      // A partial current month intentionally clips a requested full prior
      // month (including prompts such as "full September") to comparable days.
      final comparable = calendar.comparablePrior(
        current: currentMonth,
        prior: fullPrior,
        now: now,
      );
      if (comparable.end != fullPrior.end) {
        final throughToday = calendar.throughToday(currentMonth, now).end;
        boundedCurrentRange = AssistantTimeRange(
          currentRange.start,
          throughToday.isBefore(currentRange.end)
              ? throughToday
              : currentRange.end,
          label: 'this month to date',
        );
        priorRange = AssistantTimeRange(
          comparable.start,
          comparable.end,
          label: 'the same elapsed days last month',
        );
        currentLabel = 'this month to date';
        previousLabel = priorRange.label;
      }
    }
    final current = await _total(
      AssistantIntent(
        kind: intent.kind,
        metric: intent.metric,
        aggregation: intent.aggregation,
        range: boundedCurrentRange,
        compareRange: intent.compareRange,
        categoryId: intent.categoryId,
        categoryName: intent.categoryName,
        categoryIds: intent.categoryIds,
        categoryNames: intent.categoryNames,
        merchant: intent.merchant,
        direction: intent.direction,
      ),
    );
    final previous = await _total(
      AssistantIntent(
        kind: AssistantIntentKind.periodTotal,
        metric: intent.metric,
        aggregation: AssistantAggregation.sum,
        range: priorRange,
        categoryId: intent.categoryId,
        categoryIds: intent.categoryIds,
        categoryNames: intent.categoryNames,
        categoryName: intent.categoryName,
        merchant: intent.merchant,
        direction: intent.direction,
      ),
    );
    final currentByCurrency = {
      for (final bucket in current.currencyBuckets) bucket.key: bucket,
    };
    final previousByCurrency = {
      for (final bucket in previous.currencyBuckets) bucket.key: bucket,
    };
    final currencyKeys = {
      ...currentByCurrency.keys,
      ...previousByCurrency.keys,
    };
    final hasComparableScalar = currentByCurrency.length == 1 &&
        previousByCurrency.length == 1 &&
        currentByCurrency.keys.single == previousByCurrency.keys.single;
    return ComparisonQueryResult(
      current: hasComparableScalar ? current.value : null,
      previous: hasComparableScalar ? previous.value : null,
      currencyBuckets: [
        for (final key in currencyKeys)
          (
            current: currentByCurrency[key]?.amount ?? 0,
            previous: previousByCurrency[key]?.amount ?? 0,
            currencyCode: currentByCurrency[key]?.currencyCode ??
                previousByCurrency[key]?.currencyCode,
            currencySymbol: currentByCurrency[key]?.currencySymbol ??
                previousByCurrency[key]?.currencySymbol,
          ),
      ],
      currentLabel: currentLabel,
      previousLabel: previousLabel,
    );
  }

  Future<RecurringQueryResult> _recurring(AssistantIntent intent) async {
    final range = intent.range!;
    final rows = await database.select(database.recurringSeries).get();
    final items = rows
        .where(
          (row) =>
              !row.nextExpectedDate.isBefore(range.start) &&
              row.nextExpectedDate.isBefore(range.end),
        )
        .map(
          (row) => RecurringQueryItem(
            row.label,
            row.expectedAmount,
            row.nextExpectedDate,
            currencyCode: row.currencyCode,
            currencySymbol: row.currencySymbol,
          ),
        )
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return RecurringQueryResult(items);
  }

  Future<InsightsQueryResult> _insights(AssistantIntent intent) async {
    final rows = await database.select(database.insights).get();
    final items = <InsightQueryItem>[];
    final fresh = await freshClaims(
      database,
      rows.where((row) => !row.dismissed),
      calendar: calendar,
    );
    final names = await loadClaimDisplayNames(database);
    const renderer = ClaimRenderer();
    for (final row in fresh) {
      if (intent.range != null) {
        final period = DateTime.tryParse('${row.period.substring(0, 7)}-01');
        if (period == null ||
            period.isBefore(intent.range!.start) ||
            !period.isBefore(intent.range!.end)) {
          continue;
        }
      }
      final claim = const ClaimValidator().parse(row);
      if (claim == null) continue;
      final display = renderer.render(
        claim,
        categoryNames: names.categories,
        merchantNames: names.merchants,
      );
      if (display == null) continue;
      items
          .add(InsightQueryItem(row.kind, '${display.title}: ${display.body}'));
    }
    return InsightsQueryResult(items);
  }

  static bool _included(Transaction row, AssistantMetric metric) =>
      switch (metric) {
        AssistantMetric.spend => row.direction == 'debit',
        AssistantMetric.income => row.direction == 'credit',
        AssistantMetric.net => true,
      };

  static Set<String> _descendantCategoryIds(
    Set<String> selectedIds,
    Map<String, String?> parents,
  ) {
    final included = {...selectedIds};
    var changed = true;
    while (changed) {
      changed = false;
      for (final entry in parents.entries) {
        if (!included.contains(entry.key) &&
            entry.value != null &&
            included.contains(entry.value)) {
          included.add(entry.key);
          changed = true;
        }
      }
    }
    return included;
  }

  static double _signed(Transaction row, AssistantMetric metric) =>
      metric == AssistantMetric.net && row.direction == 'debit'
          ? -row.amount
          : row.amount;
}

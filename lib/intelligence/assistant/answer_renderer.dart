import '../../core/format.dart';
import '../../data/models/source_currency.dart';
import 'assistant_intent.dart';
import 'query_engine.dart';

typedef _ComparisonBucket = ({
  double current,
  double previous,
  String? currencyCode,
  String? currencySymbol,
});

class AnswerRenderer {
  const AnswerRenderer();

  String render(
    AssistantIntent intent,
    AssistantQueryResult result,
  ) =>
      switch (result) {
        TotalQueryResult(
          :final value,
          :final count,
          :final label,
          :final currencyBuckets,
          :final matchedByBrandToken,
          :final includedPayees
        ) =>
          _totalAnswer(
            intent,
            value: value,
            count: count,
            label: label,
            currencyBuckets: currencyBuckets,
            matchedByBrandToken: matchedByBrandToken,
            includedPayees: includedPayees,
          ),
        BreakdownQueryResult(:final items) => _breakdownAnswer(intent, items),
        ComparisonQueryResult(
          :final currencyBuckets,
          :final currentLabel,
          :final previousLabel,
        ) =>
          _comparisonAnswer(
            intent,
            currencyBuckets,
            currentLabel,
            previousLabel,
          ),
        RecurringQueryResult(:final items) => items.isEmpty
            ? 'There are no recurring payments due in ${formatPeriodLabel(intent.range!.label)}.'
            : items
                .map(
                  (item) =>
                      '${item.label}: ${formatSourceAmount(item.amount, currencyCode: item.currencyCode, currencySymbol: item.currencySymbol)} on ${_date(item.date)}',
                )
                .join('\n'),
        InsightsQueryResult(:final items) => items.isEmpty
            ? 'There are no active insights.'
            : items.map((item) => item.text).join('\n'),
        AssistantClarificationResult(:final refusal) =>
          '${refusal.message}${refusal.suggestions.isEmpty ? '' : '\nChoose: ${refusal.suggestions.join(' · ')}'}',
      };

  static String _totalAnswer(
    AssistantIntent intent, {
    required double? value,
    required int count,
    required String label,
    required List<AssistantCurrencyBucket> currencyBuckets,
    required String? matchedByBrandToken,
    required List<String> includedPayees,
  }) {
    final period = formatPeriodLabel(label);
    if (count == 0) {
      return _withDisclosure(
        'No ${_metricNoun(intent.metric)} transactions matched${_target(intent)} in $period.',
        _disclosure(intent),
      );
    }

    final amount = _totalValue(
      intent.aggregation,
      currencyBuckets,
      count,
      value,
    );
    final hasMultipleCurrencies = currencyBuckets.length > 1;
    final sentence = intent.aggregation == AssistantAggregation.count
        ? 'You had $count ${_metricNoun(intent.metric)} transactions${_target(intent)} in $period.'
        : hasMultipleCurrencies
            ? 'Across $count transactions in $period, you ${_verb(intent.metric)} $amount${_target(intent)}.'
            : '${_averagePrefix(intent)}$amount${_target(intent)} in $period across $count transactions.';
    final extras = <String>[
      if (hasMultipleCurrencies) 'Currency totals are kept separate.',
      if (matchedByBrandToken != null && includedPayees.isNotEmpty)
        'Included payees: ${includedPayees.join(' and ')} — matched by the word \'$matchedByBrandToken\'.',
    ];
    return _withDisclosure(sentence, _disclosure(intent, extras: extras));
  }

  static String _breakdownAnswer(
    AssistantIntent intent,
    List<BreakdownItem> items,
  ) {
    final period = formatPeriodLabel(intent.range!.label);
    if (items.isEmpty) {
      return _withDisclosure(
        'No ${_metricNoun(intent.metric)} transactions matched${_target(intent)} in $period.',
        _disclosure(intent),
      );
    }
    final amounts = items
        .map(
          (item) =>
              '${item.label}: ${formatSourceAmount(item.total, currencyCode: item.currencyCode, currencySymbol: item.currencySymbol)}',
        )
        .join('\n');
    final currencyKeys = {
      for (final item in items)
        SourceCurrency(code: item.currencyCode, symbol: item.currencySymbol)
            .bucketKey,
    };
    return _withDisclosure(
      'Here is your ${_metricNoun(intent.metric)} by category in $period:\n$amounts',
      _disclosure(
        intent,
        extras: [
          if (currencyKeys.length > 1) 'Currency totals are kept separate.',
        ],
      ),
    );
  }

  static String _comparisonAnswer(
    AssistantIntent intent,
    List<_ComparisonBucket> buckets,
    String? currentLabel,
    String? previousLabel,
  ) {
    if (buckets.isEmpty) {
      return _withDisclosure(
        'A same-currency comparison is not available for these periods.',
        _disclosure(intent),
      );
    }
    final currentPeriod = formatPeriodLabel(
      currentLabel ?? intent.range!.label,
    );
    final previousPeriod = formatPeriodLabel(
      previousLabel ?? intent.compareRange!.label,
    );
    final sentences = buckets.map((bucket) {
      final current = formatSourceAmount(
        bucket.current,
        currencyCode: bucket.currencyCode,
        currencySymbol: bucket.currencySymbol,
      );
      final previous = formatSourceAmount(
        bucket.previous,
        currencyCode: bucket.currencyCode,
        currencySymbol: bucket.currencySymbol,
      );
      final change = bucket.current - bucket.previous;
      final ratio = bucket.previous == 0 ? null : change / bucket.previous;
      final difference = formatSourceAmount(
        change,
        currencyCode: bucket.currencyCode,
        currencySymbol: bucket.currencySymbol,
      );
      return 'You ${_verb(intent.metric)} $current in $currentPeriod, compared with $previous in $previousPeriod. The difference is $difference${ratio == null ? '' : ' (${(ratio * 100).toStringAsFixed(1)}%)'}.';
    }).join('\n');
    return _withDisclosure(
      sentences,
      _disclosure(
        intent,
        extras: [
          if (buckets.length > 1) 'Currency totals are kept separate.',
        ],
      ),
    );
  }

  static String _withDisclosure(String sentence, String disclosure) =>
      '$sentence\n$disclosure';

  static String _disclosure(
    AssistantIntent intent, {
    List<String> extras = const [],
  }) =>
      'How this was counted: ${_filters(intent)}${extras.isEmpty ? '' : ' · ${extras.join(' · ')}'}';

  static String _target(AssistantIntent intent) {
    final categories = intent.categoryNames.isNotEmpty
        ? intent.categoryNames.join(' and ')
        : intent.categoryName;
    final category = categories == null ? '' : ' on $categories';
    final merchant = intent.merchant == null ? '' : ' at ${intent.merchant}';
    return '$category$merchant';
  }

  static String _metricNoun(AssistantMetric metric) => switch (metric) {
        AssistantMetric.spend => 'spending',
        AssistantMetric.income => 'income',
        AssistantMetric.net => 'net amount',
      };

  static String _verb(AssistantMetric metric) => switch (metric) {
        AssistantMetric.spend => 'spent',
        AssistantMetric.income => 'received',
        AssistantMetric.net => 'had a net amount of',
      };

  static String _averagePrefix(AssistantIntent intent) =>
      intent.aggregation == AssistantAggregation.average
          ? 'Your average ${_metricNoun(intent.metric)} was '
          : 'You ${_verb(intent.metric)} ';

  static String _totalValue(
    AssistantAggregation aggregation,
    List<AssistantCurrencyBucket> buckets,
    int count,
    double? value,
  ) {
    if (aggregation == AssistantAggregation.count) return count.toString();
    if (buckets.isEmpty) {
      return value == null ? 'total unavailable' : formatSourceAmount(value);
    }
    return buckets
        .map(
          (bucket) => formatSourceAmount(
            bucket.amount,
            currencyCode: bucket.currencyCode,
            currencySymbol: bucket.currencySymbol,
          ),
        )
        .join(' and ');
  }

  static String _filters(AssistantIntent intent) {
    final filters = <String>[
      _metric(intent.metric),
      if (intent.categoryNames.isNotEmpty)
        intent.categoryNames.join(' + ')
      else if (intent.categoryName != null)
        intent.categoryName!,
      if (intent.merchant != null) intent.merchant!,
      if (intent.direction != null) intent.direction!,
    ];
    return filters.join(' · ');
  }

  static String _metric(AssistantMetric metric) => switch (metric) {
        AssistantMetric.spend => 'Spending',
        AssistantMetric.income => 'Income',
        AssistantMetric.net => 'Net amount',
      };

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year}';
}

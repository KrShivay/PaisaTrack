import '../../core/format.dart';
import 'assistant_intent.dart';
import 'query_engine.dart';

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
          count == 0
              ? 'Period: $label\nNo matching transactions were found.\nFilters: ${_filters(intent)}'
              : 'Period: $label\nResult: ${_metric(intent.metric)} ${_totalValue(intent.aggregation, currencyBuckets, count, value)} across $count transactions.${matchedByBrandToken == null ? '' : '\nIncluded payees: ${includedPayees.join(' and ')} — matched by the word \'$matchedByBrandToken\'.'}\nFilters: ${_filters(intent)}',
        BreakdownQueryResult(:final items) => items.isEmpty
            ? 'Period: ${intent.range!.label}\nNo matching transactions were found.\nFilters: ${_filters(intent)}'
            : 'Period: ${intent.range!.label}\nResult:\n${items.map((item) => '${item.label}: ${formatSourceAmount(item.total, currencyCode: item.currencyCode, currencySymbol: item.currencySymbol)}').join('\n')}\nFilters: ${_filters(intent)}',
        ComparisonQueryResult(
          :final currencyBuckets,
          :final currentLabel,
          :final previousLabel,
        ) =>
          currencyBuckets.isEmpty
              ? 'No same-currency comparison is available.'
              : currencyBuckets.map((bucket) {
                  final change = bucket.current - bucket.previous;
                  final ratio =
                      bucket.previous == 0 ? null : change / bucket.previous;
                  final currentValue = formatSourceAmount(
                    bucket.current,
                    currencyCode: bucket.currencyCode,
                    currencySymbol: bucket.currencySymbol,
                  );
                  final previousValue = formatSourceAmount(
                    bucket.previous,
                    currencyCode: bucket.currencyCode,
                    currencySymbol: bucket.currencySymbol,
                  );
                  return 'Current period (${currentLabel ?? intent.range!.label}): $currentValue. Previous period (${previousLabel ?? intent.compareRange!.label}): $previousValue. Difference: ${formatSourceAmount(change, currencyCode: bucket.currencyCode, currencySymbol: bucket.currencySymbol)}${ratio == null ? '' : ' (${(ratio * 100).toStringAsFixed(1)}%)'}.';
                }).join('\n'),
        RecurringQueryResult(:final items) => items.isEmpty
            ? 'No recurring payments are due in ${intent.range!.label}.'
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

  static String _metric(AssistantMetric metric) => switch (metric) {
        AssistantMetric.spend => 'Spending',
        AssistantMetric.income => 'Income',
        AssistantMetric.net => 'Net amount',
      };
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
        .join(' · ');
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

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year}';
}

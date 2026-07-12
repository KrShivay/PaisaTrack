import '../../core/format.dart';
import 'assistant_intent.dart';
import 'query_engine.dart';

class AnswerRenderer {
  const AnswerRenderer();

  String render(AssistantIntent intent, AssistantQueryResult result) =>
      switch (result) {
        TotalQueryResult(:final value, :final count, :final label) => count == 0
            ? 'No transactions found for $label.'
            : '${_metric(intent.metric)} for $label: ${_value(intent.aggregation, value)} across $count transactions.',
        BreakdownQueryResult(:final items) => items.isEmpty
            ? 'No transactions found for ${intent.range!.label}.'
            : items
                .map((item) => '${item.label}: ${formatInr(item.total)}')
                .join('\n'),
        ComparisonQueryResult(
          :final current,
          :final previous,
          :final delta,
          :final percent
        ) =>
          'Current: ${formatInr(current)}. Previous: ${formatInr(previous)}. Difference: ${formatInr(delta)}${percent == null ? '' : ' (${(percent * 100).toStringAsFixed(1)}%)'}.',
        RecurringQueryResult(:final items) => items.isEmpty
            ? 'No recurring payments are due in ${intent.range!.label}.'
            : items
                .map(
                  (item) =>
                      '${item.label}: ${formatInr(item.amount)} on ${_date(item.date)}',
                )
                .join('\n'),
        InsightsQueryResult(:final items) => items.isEmpty
            ? 'There are no active insights.'
            : '${items.length} active insights: ${items.map((item) => item.kind.replaceAll('_', ' ')).join(', ')}.',
      };

  static String _metric(AssistantMetric metric) => switch (metric) {
        AssistantMetric.spend => 'Spending',
        AssistantMetric.income => 'Income',
        AssistantMetric.net => 'Net amount',
      };
  static String _value(AssistantAggregation aggregation, double value) =>
      aggregation == AssistantAggregation.count
          ? value.round().toString()
          : formatInr(value);
  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year}';
}

import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/intelligence/assistant/assistant_intent_classifier.dart';

void main() {
  const classifier = AssistantIntentClassifier();
  final today = DateTime(2026, 7, 13);
  const categories = ['Food', 'Bank Fees', 'Travel'];

  Map<String, Object?>? classify(String question) => classifier.classify(
        question,
        today: today,
        categoryNames: categories,
      );

  test('classifies common totals without invoking a language model', () {
    expect(classify('How much did I spend this month?'), {
      'intent': 'period_total',
      'metric': 'spend',
      'aggregation': 'sum',
      'time_range': {'kind': 'month', 'month': '2026-07'},
    });
    expect(classify('How many payments did I make in the last 30 days?'), {
      'intent': 'period_total',
      'metric': 'spend',
      'aggregation': 'count',
      'time_range': {'kind': 'last_n_days', 'n_days': 30},
    });
    expect(classify('What is my total outflow for July 2026?'), {
      'intent': 'period_total',
      'metric': 'spend',
      'aggregation': 'sum',
      'filter': {'direction': 'debit'},
      'time_range': {'kind': 'month', 'month': '2026-07'},
    });
    expect(classify('Show my inflow this month'), {
      'intent': 'period_total',
      'metric': 'income',
      'aggregation': 'sum',
      'filter': {'direction': 'credit'},
      'time_range': {'kind': 'month', 'month': '2026-07'},
    });
    expect(classify('Give me a summary of what came in during July 2026'), {
      'intent': 'period_total',
      'metric': 'income',
      'aggregation': 'sum',
      'filter': {'direction': 'credit'},
      'time_range': {'kind': 'month', 'month': '2026-07'},
    });
    expect(classify('Where has all the cash gone lately?'), {
      'intent': 'period_total',
      'metric': 'spend',
      'aggregation': 'sum',
      'time_range': {'kind': 'last_n_days', 'n_days': 30},
    });
  });

  test('resolves categories and merchant names deterministically', () {
    expect(classify('How much did I pay in bank fees?'), {
      'intent': 'period_total',
      'metric': 'spend',
      'aggregation': 'sum',
      'filter': {'category': 'Bank Fees'},
      'time_range': {'kind': 'month', 'month': '2026-07'},
    });
    expect(classify('How much did I spend at Amazon this month?'), {
      'intent': 'merchant_lookup',
      'metric': 'spend',
      'aggregation': 'sum',
      'filter': {'merchant': 'Amazon'},
      'time_range': {'kind': 'month', 'month': '2026-07'},
    });
    expect(classify('How much did I spend with Zomato last month?'), {
      'intent': 'merchant_lookup',
      'metric': 'spend',
      'aggregation': 'sum',
      'filter': {'merchant': 'Zomato'},
      'time_range': {'kind': 'month', 'month': '2026-06'},
    });
    expect(classify('Show Amazon activity'), {
      'intent': 'merchant_lookup',
      'metric': 'spend',
      'aggregation': 'sum',
      'filter': {'merchant': 'Amazon'},
      'time_range': {'kind': 'all_time'},
    });
    expect(classify('Show recent transactions'), {
      'intent': 'period_total',
      'metric': 'spend',
      'aggregation': 'sum',
      'time_range': {'kind': 'last_n_days', 'n_days': 30},
    });
    expect(classify('Show debit transactions'), {
      'intent': 'period_total',
      'metric': 'spend',
      'aggregation': 'sum',
      'filter': {'direction': 'debit'},
      'time_range': {'kind': 'month', 'month': '2026-07'},
    });
  });

  test('resolves a single distinctive token to a multi-word category', () {
    // Device S1 regression: "food" must resolve to "Food & Dining" instead of
    // falling through to a merchant lookup that returns nothing.
    const multiWord = AssistantIntentClassifier();
    Map<String, Object?>? ask(String q, List<String> cats) =>
        multiWord.classify(
          q,
          today: today,
          categoryNames: cats,
        );

    expect(
        ask('How much did I spend on food this month?', const [
          'Food & Dining',
          'Travel',
        ]),
        {
          'intent': 'period_total',
          'metric': 'spend',
          'aggregation': 'sum',
          'filter': {'category': 'Food & Dining'},
          'time_range': {'kind': 'month', 'month': '2026-07'},
        });

    // A token shared by two categories is ambiguous, so it must NOT auto-pick a
    // category (fail closed) — it falls through to a merchant lookup here.
    final ambiguous =
        ask('How much on food this month?', const ['Fast Food', 'Food Court']);
    expect(ambiguous?['filter'], isNot(contains('category')));
  });

  test('resolves years, quarters, and explicit ranges locally', () {
    expect(classify('How much did I spend in 2023?'), {
      'intent': 'period_total',
      'metric': 'spend',
      'aggregation': 'sum',
      'time_range': {
        'kind': 'range',
        'start': '2023-01-01',
        'end': '2023-12-31',
      },
    });
    expect(classify('What is my year to date income?'), {
      'intent': 'period_total',
      'metric': 'income',
      'aggregation': 'sum',
      'time_range': {
        'kind': 'range',
        'start': '2026-01-01',
        'end': '2026-07-13',
      },
    });
    expect(classify('Total expenses in Q2 2025'), {
      'intent': 'period_total',
      'metric': 'spend',
      'aggregation': 'sum',
      'time_range': {
        'kind': 'range',
        'start': '2025-04-01',
        'end': '2025-06-30',
      },
    });
    expect(classify('Spend from 1 June 2026 to 10 July 2026'), {
      'intent': 'period_total',
      'metric': 'spend',
      'aggregation': 'sum',
      'time_range': {
        'kind': 'range',
        'start': '2026-06-01',
        'end': '2026-07-10',
      },
    });
    expect(classify('Spend between 2026-06-01 and 2026-06-30'), {
      'intent': 'period_total',
      'metric': 'spend',
      'aggregation': 'sum',
      'time_range': {
        'kind': 'range',
        'start': '2026-06-01',
        'end': '2026-06-30',
      },
    });
  });

  test('builds comparisons and recurring ranges from relative dates', () {
    expect(classify('Why is spending higher than last month?'), {
      'intent': 'month_over_month',
      'metric': 'spend',
      'aggregation': 'sum',
      'time_range': {'kind': 'month', 'month': '2026-07'},
      'compare_to': {'kind': 'month', 'month': '2026-06'},
    });
    expect(classify('What subscriptions renew this week?'), {
      'intent': 'upcoming_recurring',
      'time_range': {
        'kind': 'range',
        'start': '2026-07-13',
        'end': '2026-07-19',
      },
    });
    expect(classify('Anything unusual in my spending?'), {
      'intent': 'active_insights',
    });
    expect(classify('Compare June 2025 vs May 2025'), {
      'intent': 'month_over_month',
      'metric': 'spend',
      'aggregation': 'sum',
      'time_range': {'kind': 'month', 'month': '2025-06'},
      'compare_to': {'kind': 'month', 'month': '2025-05'},
    });
    expect(classify('Compare last month with the previous month'), {
      'intent': 'month_over_month',
      'metric': 'spend',
      'aggregation': 'sum',
      'time_range': {'kind': 'month', 'month': '2026-06'},
      'compare_to': {'kind': 'month', 'month': '2026-05'},
    });
    expect(classify('Compare 2025 vs 2024'), {
      'intent': 'month_over_month',
      'metric': 'spend',
      'aggregation': 'sum',
      'time_range': {
        'kind': 'range',
        'start': '2025-01-01',
        'end': '2025-12-31',
      },
      'compare_to': {
        'kind': 'range',
        'start': '2024-01-01',
        'end': '2024-12-31',
      },
    });
    expect(classify('Compare Q2 2026 vs Q1 2026'), {
      'intent': 'month_over_month',
      'metric': 'spend',
      'aggregation': 'sum',
      'time_range': {
        'kind': 'range',
        'start': '2026-04-01',
        'end': '2026-06-30',
      },
      'compare_to': {
        'kind': 'range',
        'start': '2026-01-01',
        'end': '2026-03-31',
      },
    });
    expect(classify('Put June 2026 next to July 2026 for me'), {
      'intent': 'month_over_month',
      'metric': 'spend',
      'aggregation': 'sum',
      'time_range': {'kind': 'month', 'month': '2026-06'},
      'compare_to': {'kind': 'month', 'month': '2026-07'},
    });
    expect(classify('What bills are about to hit?'), {
      'intent': 'upcoming_recurring',
    });
  });

  test('leaves ambiguous and unsupported filters for the guarded fallback', () {
    expect(classify('Analyse my finances in your own way'), isNull);
    expect(classify('Show payments above ₹5,000'), {
      'intent': 'unsupported',
    });
    expect(classify('Which stock should I buy?'), {
      'intent': 'unsupported',
    });
    expect(classify('Spend from 2026-02-30 to 2026-03-02'), isNull);
    expect(classify('How much did I spend in fiscal year 2025?'), isNull);
  });

  test('covers common conversational finance paraphrases locally', () {
    expect(classify('How much money went out last month?'), {
      'intent': 'period_total',
      'metric': 'spend',
      'aggregation': 'sum',
      'filter': {'direction': 'debit'},
      'time_range': {'kind': 'month', 'month': '2026-06'},
    });
    expect(classify('Show my earnings for 2025'), {
      'intent': 'period_total',
      'metric': 'income',
      'aggregation': 'sum',
      'time_range': {
        'kind': 'range',
        'start': '2025-01-01',
        'end': '2025-12-31',
      },
    });
    expect(classify('What was left over last month?'), {
      'intent': 'period_total',
      'metric': 'net',
      'aggregation': 'sum',
      'time_range': {'kind': 'month', 'month': '2026-06'},
    });
    expect(classify('How much did I spend over the last month?'), {
      'intent': 'period_total',
      'metric': 'spend',
      'aggregation': 'sum',
      'time_range': {'kind': 'month', 'month': '2026-06'},
    });
    expect(classify('Break down my spending for June 2026'), {
      'intent': 'category_breakdown',
      'metric': 'spend',
      'aggregation': 'breakdown',
      'time_range': {'kind': 'month', 'month': '2026-06'},
    });
    expect(classify('List Uber payments this month'), {
      'intent': 'merchant_lookup',
      'metric': 'spend',
      'aggregation': 'sum',
      'filter': {'merchant': 'Uber'},
      'time_range': {'kind': 'month', 'month': '2026-07'},
    });
    expect(classify('What did I pay Amazon last month?'), {
      'intent': 'merchant_lookup',
      'metric': 'spend',
      'aggregation': 'sum',
      'filter': {'merchant': 'Amazon'},
      'time_range': {'kind': 'month', 'month': '2026-06'},
    });
    expect(classify('What is the difference between June and July?'), {
      'intent': 'month_over_month',
      'metric': 'spend',
      'aggregation': 'sum',
      'time_range': {'kind': 'month', 'month': '2026-06'},
      'compare_to': {'kind': 'month', 'month': '2026-07'},
    });
    expect(classify('Is spending up from last month?'), {
      'intent': 'month_over_month',
      'metric': 'spend',
      'aggregation': 'sum',
      'time_range': {'kind': 'month', 'month': '2026-07'},
      'compare_to': {'kind': 'month', 'month': '2026-06'},
    });
    expect(classify('Which payments are coming up?'), {
      'intent': 'upcoming_recurring',
    });
    expect(classify('Any spending anomalies?'), {
      'intent': 'active_insights',
    });
    expect(classify('Show expenses from the past week'), {
      'intent': 'period_total',
      'metric': 'spend',
      'aggregation': 'sum',
      'time_range': {'kind': 'last_n_days', 'n_days': 7},
    });
    expect(classify('Show recent transactions'), {
      'intent': 'period_total',
      'metric': 'spend',
      'aggregation': 'sum',
      'time_range': {'kind': 'last_n_days', 'n_days': 30},
    });
  });
}

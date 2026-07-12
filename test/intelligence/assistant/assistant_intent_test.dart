import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/intelligence/assistant/assistant_intent.dart';

void main() {
  final now = DateTime.utc(2026, 7, 12);
  IntentValidator validator() => IntentValidator(
        categories: const {'food': 'Food', 'travel': 'Travel'},
        clock: () => now,
      );

  test('accepts every whitelisted intent', () {
    final fixtures = <Map<String, Object?>>[
      {
        'intent': 'period_total',
        'metric': 'spend',
        'aggregation': 'sum',
        'time_range': {'kind': 'month', 'month': '2026-07'},
      },
      {
        'intent': 'category_breakdown',
        'aggregation': 'breakdown',
        'time_range': {'kind': 'last_n_days', 'n_days': 30},
      },
      {
        'intent': 'merchant_lookup',
        'filter': {'merchant': '50%_Cafe\\'},
        'time_range': {'kind': 'month', 'month': '2026-07'},
      },
      {
        'intent': 'month_over_month',
        'metric': 'spend',
        'time_range': {'kind': 'month', 'month': '2026-07'},
        'compare_to': {'kind': 'month', 'month': '2026-06'},
      },
      {'intent': 'upcoming_recurring'},
      {'intent': 'active_insights'},
    ];
    for (final fixture in fixtures) {
      expect(
        validator().validate(fixture),
        isA<ValidIntent>(),
        reason: '${fixture['intent']}',
      );
    }
  });

  test(
      'rejects unsupported, unknown category, malformed date, and SQL-shaped fields',
      () {
    expect(
      validator().validate({'intent': 'unsupported'}),
      isA<InvalidIntent>(),
    );
    expect(
      validator().validate({
        'intent': 'period_total',
        'filter': {'category': 'Dining'},
        'time_range': {'kind': 'month', 'month': '2026-07'},
      }),
      isA<InvalidIntent>(),
    );
    expect(
      validator().validate({
        'intent': 'period_total',
        'time_range': {'kind': 'month', 'month': '2026-13'},
      }),
      isA<InvalidIntent>(),
    );
    expect(
      assistantIntentSchema['properties'].toString(),
      isNot(contains('sql')),
    );
  });

  test('category resolution is exact then case-insensitive', () {
    final result = validator().validate({
      'intent': 'period_total',
      'filter': {'category': 'fOoD'},
      'time_range': {'kind': 'month', 'month': '2026-07'},
    }) as ValidIntent;
    expect(result.intent.categoryId, 'food');
    expect(result.intent.categoryName, 'Food');
  });
}

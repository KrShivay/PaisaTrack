enum AssistantIntentKind {
  periodTotal('period_total'),
  categoryBreakdown('category_breakdown'),
  merchantLookup('merchant_lookup'),
  monthOverMonth('month_over_month'),
  upcomingRecurring('upcoming_recurring'),
  activeInsights('active_insights');

  const AssistantIntentKind(this.id);
  final String id;
}

enum AssistantMetric { spend, income, net }

enum AssistantAggregation { sum, count, average, breakdown }

class AssistantTimeRange {
  const AssistantTimeRange(this.start, this.end, {required this.label});
  final DateTime start;
  final DateTime end;
  final String label;
}

class AssistantIntent {
  const AssistantIntent({
    required this.kind,
    required this.metric,
    required this.aggregation,
    this.range,
    this.compareRange,
    this.categoryId,
    this.categoryName,
    this.merchant,
    this.direction,
  });

  final AssistantIntentKind kind;
  final AssistantMetric metric;
  final AssistantAggregation aggregation;
  final AssistantTimeRange? range;
  final AssistantTimeRange? compareRange;
  final String? categoryId;
  final String? categoryName;
  final String? merchant;
  final String? direction;
}

class AssistantRefusal {
  const AssistantRefusal(this.message, {this.suggestions = const []});
  final String message;
  final List<String> suggestions;
}

sealed class IntentValidationResult {
  const IntentValidationResult();
}

final class ValidIntent extends IntentValidationResult {
  const ValidIntent(this.intent);
  final AssistantIntent intent;
}

final class InvalidIntent extends IntentValidationResult {
  const InvalidIntent(this.refusal);
  final AssistantRefusal refusal;
}

const assistantIntentSchema = <String, Object?>{
  'type': 'object',
  'required': ['intent'],
  'additionalProperties': false,
  'properties': {
    'intent': {
      'type': 'string',
      'enum': [
        'period_total',
        'category_breakdown',
        'merchant_lookup',
        'month_over_month',
        'upcoming_recurring',
        'active_insights',
        'unsupported',
      ],
    },
    'metric': {
      'type': 'string',
      'enum': ['spend', 'income', 'net'],
    },
    'filter': {
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        'category': {'type': 'string'},
        'merchant': {'type': 'string'},
        'direction': {
          'type': 'string',
          'enum': ['debit', 'credit'],
        },
      },
    },
    'time_range': {'type': 'object'},
    'aggregation': {
      'type': 'string',
      'enum': ['sum', 'count', 'average', 'breakdown'],
    },
    'compare_to': {'type': 'object'},
  },
};

class IntentValidator {
  const IntentValidator({required this.categories, this.clock = DateTime.now});

  final Map<String, String> categories;
  final DateTime Function() clock;

  IntentValidationResult validate(Map<String, Object?> json) {
    const suggestions = [
      'How much did I spend this month?',
      'Where did my money go this month?',
      'What subscriptions are due soon?',
    ];
    final id = json['intent'];
    final kind =
        AssistantIntentKind.values.where((e) => e.id == id).firstOrNull;
    if (kind == null) {
      return const InvalidIntent(
        AssistantRefusal(
          'I can answer questions about totals, categories, merchants, recurring payments, comparisons, and active insights.',
          suggestions: suggestions,
        ),
      );
    }
    final filter = _stringMap(json['filter']);
    final categoryHint = filter?['category'] as String?;
    String? categoryId;
    String? categoryName;
    if (categoryHint != null) {
      final match = categories.entries
          .where(
            (entry) =>
                entry.value.toLowerCase() == categoryHint.trim().toLowerCase(),
          )
          .firstOrNull;
      if (match == null) {
        return InvalidIntent(
          AssistantRefusal(
            "I don't see a category called '$categoryHint'.",
            suggestions: suggestions,
          ),
        );
      }
      categoryId = match.key;
      categoryName = match.value;
    }
    final merchant = (filter?['merchant'] as String?)?.trim();
    if (kind == AssistantIntentKind.merchantLookup &&
        (merchant == null || merchant.isEmpty)) {
      return const InvalidIntent(
        AssistantRefusal(
          'Tell me which merchant to look up.',
          suggestions: suggestions,
        ),
      );
    }
    final range = kind == AssistantIntentKind.activeInsights
        ? _optionalRange(json['time_range'])
        : _range(
            json['time_range'],
            upcoming: kind == AssistantIntentKind.upcomingRecurring,
          );
    if (kind != AssistantIntentKind.activeInsights && range == null) {
      return const InvalidIntent(
        AssistantRefusal(
          'I could not understand that time range.',
          suggestions: suggestions,
        ),
      );
    }
    final compare = kind == AssistantIntentKind.monthOverMonth
        ? _range(json['compare_to'])
        : null;
    if (kind == AssistantIntentKind.monthOverMonth && compare == null) {
      return const InvalidIntent(
        AssistantRefusal(
          'Choose two valid periods to compare.',
          suggestions: suggestions,
        ),
      );
    }
    final metric = AssistantMetric.values
            .where((e) => e.name == json['metric'])
            .firstOrNull ??
        AssistantMetric.spend;
    final aggregation = AssistantAggregation.values
            .where((e) => e.name == json['aggregation'])
            .firstOrNull ??
        (kind == AssistantIntentKind.categoryBreakdown
            ? AssistantAggregation.breakdown
            : AssistantAggregation.sum);
    if (kind == AssistantIntentKind.categoryBreakdown &&
        aggregation != AssistantAggregation.breakdown) {
      return const InvalidIntent(
        AssistantRefusal(
          'Category questions require a breakdown.',
          suggestions: suggestions,
        ),
      );
    }
    return ValidIntent(
      AssistantIntent(
        kind: kind,
        metric: metric,
        aggregation: aggregation,
        range: range,
        compareRange: compare,
        categoryId: categoryId,
        categoryName: categoryName,
        merchant: merchant,
        direction: filter?['direction'] as String?,
      ),
    );
  }

  AssistantTimeRange? _optionalRange(Object? value) =>
      value == null ? null : _range(value);

  AssistantTimeRange? _range(Object? value, {bool upcoming = false}) {
    if (value == null && upcoming) {
      final start = _day(clock().toUtc());
      return AssistantTimeRange(
        start,
        start.add(const Duration(days: 30)),
        label: 'the next 30 days',
      );
    }
    final map = _stringMap(value);
    if (map == null) return null;
    final now = _day(clock().toUtc());
    final kind = map['kind'];
    DateTime? start;
    DateTime? end;
    String? label;
    if (kind == 'month') {
      final parts = (map['month'] as String? ?? '').split('-');
      if (parts.length != 2) return null;
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      if (year == null || month == null || month < 1 || month > 12) return null;
      start = DateTime.utc(year, month);
      end = DateTime.utc(year, month + 1);
      label = '${parts[0]}-${parts[1]}';
    } else if (kind == 'last_n_days') {
      final days = map['n_days'];
      if (days is! int || days < 1 || days > 3660) return null;
      end = now.add(const Duration(days: 1));
      start = end.subtract(Duration(days: days));
      label = 'the last $days days';
    } else if (kind == 'range') {
      start = DateTime.tryParse(map['start'] as String? ?? '')?.toUtc();
      final inclusiveEnd =
          DateTime.tryParse(map['end'] as String? ?? '')?.toUtc();
      if (inclusiveEnd != null) end = inclusiveEnd.add(const Duration(days: 1));
      label = '${map['start']} to ${map['end']}';
    } else if (kind == 'all_time') {
      start = DateTime.utc(1970);
      end = now.add(const Duration(days: 1));
      label = 'all time';
    }
    if (start == null || end == null || !start.isBefore(end)) return null;
    if (!upcoming && start.isAfter(now)) return null;
    return AssistantTimeRange(start, end, label: label!);
  }

  static DateTime _day(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
  static Map<String, Object?>? _stringMap(Object? value) =>
      value is Map ? Map<String, Object?>.from(value) : null;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

import '../../core/financial_calendar.dart';
import '../../core/format.dart';

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

class AssistantCategoryOption {
  const AssistantCategoryOption({
    required this.id,
    required this.name,
    this.parentId,
  });

  final String id;
  final String name;
  final String? parentId;
}

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
    this.categoryIds = const [],
    this.categoryNames = const [],
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
  final List<String> categoryIds;
  final List<String> categoryNames;
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

/// Shape shared by `time_range` and `compare_to`. Fields are kind-dependent
/// (only one of month/n_days/start+end applies per `kind`), so this is left
/// permissive here — [IntentValidator._range] enforces the per-kind contract.
const _timeRangeSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'kind': {
      'type': 'string',
      'enum': ['month', 'last_n_days', 'range', 'all_time'],
    },
    'month': {'type': 'string'},
    'n_days': {'type': 'integer'},
    'start': {'type': 'string'},
    'end': {'type': 'string'},
  },
};

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
        'categories': {
          'type': 'array',
          'items': {'type': 'string'},
          'minItems': 2,
          'maxItems': 5,
        },
        'merchant': {'type': 'string'},
        'direction': {
          'type': 'string',
          'enum': ['debit', 'credit'],
        },
      },
    },
    'time_range': _timeRangeSchema,
    'aggregation': {
      'type': 'string',
      'enum': ['sum', 'count', 'average', 'breakdown'],
    },
    'compare_to': _timeRangeSchema,
  },
};

class IntentValidator {
  IntentValidator({
    required this.categories,
    FinancialCalendar? calendar,
    this.clock = DateTime.now,
  }) : calendar = calendar ?? FinancialCalendar();

  final Map<String, String> categories;
  final FinancialCalendar calendar;
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
    if (json.containsKey('filter') && filter == null) {
      return const InvalidIntent(
        AssistantRefusal(
          'I could not resolve the requested filters safely.',
          suggestions: suggestions,
        ),
      );
    }
    final categoryEncodings = [
      'category',
      'categories',
      'category_id',
      'category_ids',
    ].where((key) => filter?.containsKey(key) == true).length;
    final rawCategoryNames = filter?['categories'];
    if (categoryEncodings > 1 ||
        (filter?.containsKey('category') == true &&
            filter?['category'] is! String) ||
        (filter?.containsKey('category_id') == true &&
            filter?['category_id'] is! String) ||
        (filter?.containsKey('categories') == true &&
            (rawCategoryNames is! List ||
                rawCategoryNames.length < 2 ||
                rawCategoryNames.length > 5 ||
                rawCategoryNames.any((value) => value is! String)))) {
      return const InvalidIntent(
        AssistantRefusal(
          'I could not resolve the requested categories safely.',
          suggestions: suggestions,
        ),
      );
    }
    final categoryHints = <String>[
      if (filter?['category'] case final String category) category,
      if (rawCategoryNames is List<Object?>) ...rawCategoryNames.cast<String>(),
    ];
    final selectedCategories = <MapEntry<String, String>>[];
    final categoryIdHints = <String>[
      if (filter?['category_id'] case final String categoryId) categoryId,
    ];
    final rawCategoryIds = filter?['category_ids'];
    if (filter?.containsKey('category_ids') == true &&
        (rawCategoryIds is! List ||
            rawCategoryIds.length < 2 ||
            rawCategoryIds.length > 5 ||
            rawCategoryIds.any((value) => value is! String))) {
      return const InvalidIntent(
        AssistantRefusal(
          'I could not resolve the requested categories safely.',
          suggestions: suggestions,
        ),
      );
    }
    if (rawCategoryIds is List<Object?>) {
      categoryIdHints.addAll(rawCategoryIds.cast<String>());
    }
    for (final categoryId in categoryIdHints) {
      final name = categories[categoryId];
      if (name == null) {
        return InvalidIntent(
          AssistantRefusal(
            "I don't see a category called '$categoryId'.",
            suggestions: suggestions,
          ),
        );
      }
      if (!selectedCategories.any((item) => item.key == categoryId)) {
        selectedCategories.add(MapEntry(categoryId, name));
      }
    }
    for (final categoryHint in categoryHints) {
      final matches = categories.entries.where((entry) {
        return entry.value.trim().toLowerCase() ==
            categoryHint.trim().toLowerCase();
      }).toList(growable: false);
      if (matches.isEmpty) {
        return InvalidIntent(
          AssistantRefusal(
            "I don't see a category called '$categoryHint'.",
            suggestions: suggestions,
          ),
        );
      }
      if (matches.length > 1) {
        return InvalidIntent(
          AssistantRefusal(
            "I found more than one category called '${categoryHint.trim()}'. Please choose a category with a unique name.",
            suggestions: suggestions,
          ),
        );
      }
      final match = matches.single;
      if (!selectedCategories.any((item) => item.key == match.key)) {
        selectedCategories.add(match);
      }
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
        categoryId: selectedCategories.length == 1
            ? selectedCategories.single.key
            : null,
        categoryName: selectedCategories.length == 1
            ? selectedCategories.single.value
            : null,
        categoryIds: selectedCategories.map((item) => item.key).toList(),
        categoryNames: selectedCategories.map((item) => item.value).toList(),
        merchant: merchant,
        direction: filter?['direction'] as String?,
      ),
    );
  }

  AssistantTimeRange? _optionalRange(Object? value) =>
      value == null ? null : _range(value);

  AssistantTimeRange? _range(Object? value, {bool upcoming = false}) {
    final localNow = calendar.localDate(clock());
    final today = calendar.day(localNow.year, localNow.month, localNow.day);
    if (value == null && upcoming) {
      final start = today.start;
      return AssistantTimeRange(
        start,
        calendar.day(localNow.year, localNow.month, localNow.day + 30).start,
        label: 'the next 30 days',
      );
    }
    final map = _stringMap(value);
    if (map == null) return null;
    final now = today.start;
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
      final period = calendar.month(year, month);
      start = period.start;
      end = period.end;
      label = formatMonthYear(DateTime(year, month));
    } else if (kind == 'last_n_days') {
      final days = map['n_days'];
      if (days is! int || days < 1 || days > 3660) return null;
      end = today.end;
      final firstDay = DateTime.utc(
        localNow.year,
        localNow.month,
        localNow.day - days + 1,
      );
      start = calendar.day(firstDay.year, firstDay.month, firstDay.day).start;
      label = 'the last $days days';
    } else if (kind == 'range') {
      start = _parseLocalDate(map['start'] as String?);
      final inclusiveEnd = _parseLocalDate(map['end'] as String?);
      if (inclusiveEnd != null) {
        end = calendar.dayContaining(inclusiveEnd).end;
      }
      final startLabel = map['start'] as String?;
      final endLabel = map['end'] as String?;
      label = startLabel == null || endLabel == null
          ? 'selected dates'
          : formatIsoDateRange(startLabel, endLabel);
    } else if (kind == 'all_time') {
      start = calendar.day(1970, 1, 1).start;
      end = today.end;
      label = 'all time';
    }
    if (start == null || end == null || !start.isBefore(end)) return null;
    if (!upcoming && start.isAfter(now)) return null;
    return AssistantTimeRange(start, end, label: label!);
  }

  DateTime? _parseLocalDate(String? value) {
    final parts = (value ?? '').split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    final local = DateTime.utc(year, month, day);
    if (local.year != year || local.month != month || local.day != day) {
      return null;
    }
    return calendar.day(year, month, day).start;
  }

  static Map<String, Object?>? _stringMap(Object? value) =>
      value is Map ? Map<String, Object?>.from(value) : null;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

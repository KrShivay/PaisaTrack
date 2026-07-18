class AssistantIntentClassifier {
  const AssistantIntentClassifier();

  Map<String, Object?>? classify(
    String question, {
    required DateTime today,
    required Iterable<String> categoryNames,
  }) {
    final normalized = _normalize(question);
    if (normalized.isEmpty) return null;
    if (_hasUnsupportedAmountFilter(normalized) ||
        _isClearlyUnsupported(normalized)) {
      return {'intent': 'unsupported'};
    }
    final category = _matchCategory(normalized, categoryNames);
    final metric = _metric(normalized);
    final aggregation = _aggregation(normalized);
    final range = _range(normalized, today);
    // A bare year inside this unsupported construct must not masquerade as a
    // supported calendar-year range.
    if (_containsPhrase(normalized, 'fiscal year')) return null;

    if (_containsAny(normalized, const [
      'subscription',
      'subscriptions',
      'recurring',
      'renew',
      'renews',
      'due soon',
      'upcoming payment',
      'about to hit',
      'bill due',
      'bills due',
      'coming up',
      'payments due',
      'autopay',
      'auto debit',
    ])) {
      return {
        'intent': 'upcoming_recurring',
        if (_upcomingRange(normalized, today) case final upcomingRange?)
          'time_range': upcomingRange,
      };
    }

    if (_containsAny(normalized, const [
      'budget alert',
      'budget alerts',
      'active insight',
      'active insights',
      'spending insight',
      'spending insights',
      'anything unusual',
      'unusual spending',
      'spending anomaly',
      'spending anomalies',
      'anomaly',
      'anomalies',
      'anything notable',
    ])) {
      return {'intent': 'active_insights'};
    }

    final filter = <String, Object?>{};
    if (category != null) filter['category'] = category;
    if (_direction(normalized) case final direction?) {
      filter['direction'] = direction;
    }

    if (_isComparison(normalized)) {
      final ranges = _comparisonRanges(normalized, today);
      return {
        'intent': 'month_over_month',
        'metric': metric,
        'aggregation': 'sum',
        if (filter.isNotEmpty) 'filter': filter,
        'time_range': ranges.$1,
        'compare_to': ranges.$2,
      };
    }

    if (_containsAny(normalized, const [
      'where did my money go',
      'where does my money go',
      'category breakdown',
      'break down',
      'breakdown by category',
      'by category',
      'which categories',
      'top categories',
      'spending categories',
      'split by category',
    ])) {
      return {
        'intent': 'category_breakdown',
        'metric': metric,
        'aggregation': 'breakdown',
        'time_range': range ?? _monthRange(today),
      };
    }

    final merchant = category == null ? _merchant(question) : null;
    if (merchant != null) {
      filter['merchant'] = merchant;
      return {
        'intent': 'merchant_lookup',
        'metric': metric,
        'aggregation': aggregation,
        'filter': filter,
        'time_range': range ?? const {'kind': 'all_time'},
      };
    }

    if (!_looksLikeFinancialTotal(normalized) && category == null) return null;
    if (range == null && _hasUnresolvedTimeReference(normalized)) return null;
    return {
      'intent': 'period_total',
      'metric': metric,
      'aggregation': aggregation,
      if (filter.isNotEmpty) 'filter': filter,
      'time_range': range ?? _monthRange(today),
    };
  }

  static String _metric(String text) {
    if (_containsAny(text, const [
      'income',
      'inflow',
      'cash in',
      'earned',
      'received',
      'salary',
      'credited',
      'credits',
      'came in',
      'earnings',
      'money in',
    ])) {
      return 'income';
    }
    if (_containsAny(text, const [
      'net',
      'saved',
      'left over',
      'balance change',
    ])) {
      return 'net';
    }
    return 'spend';
  }

  static String? _direction(String text) {
    if (_containsAny(text, const [
      'debit transaction',
      'debit transactions',
      'debits',
      'debited',
      'outflow',
      'cash out',
      'money out',
      'went out',
    ])) {
      return 'debit';
    }
    if (_containsAny(text, const [
      'credit transaction',
      'credit transactions',
      'credits',
      'credited',
      'inflow',
      'cash in',
      'money in',
      'came in',
    ])) {
      return 'credit';
    }
    return null;
  }

  static String _aggregation(String text) {
    if (_containsAny(text, const ['how many', 'count', 'number of'])) {
      return 'count';
    }
    if (_containsAny(text, const ['average', 'avg'])) return 'average';
    return 'sum';
  }

  static Map<String, Object?>? _range(String text, DateTime today) {
    if (_containsAny(
      text,
      const ['all time', 'all-time', 'ever', 'lifetime'],
    )) {
      return const {'kind': 'all_time'};
    }
    if (_containsPhrase(text, 'today')) {
      final date = _date(today);
      return {'kind': 'range', 'start': date, 'end': date};
    }
    if (_containsPhrase(text, 'yesterday')) {
      final yesterday = today.subtract(const Duration(days: 1));
      final date = _date(yesterday);
      return {'kind': 'range', 'start': date, 'end': date};
    }
    if (_containsAny(text, const ['lately', 'recent'])) {
      return const {'kind': 'last_n_days', 'n_days': 30};
    }
    if (_containsAny(text, const ['year to date', 'ytd'])) {
      return _inclusiveRange(DateTime(today.year), today);
    }
    if (_containsAny(text, const ['this year', 'current year'])) {
      return _yearRange(today.year);
    }
    if (_containsAny(text, const ['last year', 'previous year'])) {
      return _yearRange(today.year - 1);
    }
    if (_containsAny(text, const ['this quarter', 'current quarter'])) {
      return _quarterRange(today.year, ((today.month - 1) ~/ 3) + 1);
    }
    if (_containsPhrase(text, 'last quarter')) {
      final currentQuarter = ((today.month - 1) ~/ 3) + 1;
      return currentQuarter == 1
          ? _quarterRange(today.year - 1, 4)
          : _quarterRange(today.year, currentQuarter - 1);
    }
    if (_explicitDateRange(text) case final explicit?) return explicit;
    if (_mentionsExplicitDateRange(text)) return null;
    final quarterMatch =
        RegExp(r'\bq([1-4])(?:\s+(20\d{2}))?\b').firstMatch(text);
    if (quarterMatch != null) {
      final quarter = int.parse(quarterMatch.group(1)!);
      final year = int.tryParse(quarterMatch.group(2) ?? '') ?? today.year;
      return _quarterRange(year, quarter);
    }
    final dayMatch =
        RegExp(r'\b(?:last|past)\s+(\d{1,4})\s+days?\b').firstMatch(text);
    if (dayMatch != null) {
      final days = int.parse(dayMatch.group(1)!);
      if (days >= 1 && days <= 3660) {
        return {'kind': 'last_n_days', 'n_days': days};
      }
    }
    final weekMatch =
        RegExp(r'\b(?:last|past)\s+(\d{1,3})\s+weeks?\b').firstMatch(text);
    if (weekMatch != null) {
      final days = int.parse(weekMatch.group(1)!) * 7;
      if (days <= 3660) return {'kind': 'last_n_days', 'n_days': days};
    }
    if (_containsPhrase(text, 'this week')) {
      final start = today.subtract(Duration(days: today.weekday - 1));
      return {'kind': 'range', 'start': _date(start), 'end': _date(today)};
    }
    if (_containsPhrase(text, 'last week')) {
      final thisMonday = today.subtract(Duration(days: today.weekday - 1));
      final start = thisMonday.subtract(const Duration(days: 7));
      final end = thisMonday.subtract(const Duration(days: 1));
      return {'kind': 'range', 'start': _date(start), 'end': _date(end)};
    }
    if (_containsPhrase(text, 'past week')) {
      return const {'kind': 'last_n_days', 'n_days': 7};
    }
    if (_containsAny(text, const ['last month', 'previous month'])) {
      return _monthRange(DateTime(today.year, today.month - 1));
    }
    if (_containsAny(text, const ['this month', 'current month'])) {
      return _monthRange(today);
    }

    for (var index = 0; index < _months.length; index++) {
      final name = _months[index];
      final match =
          RegExp('\\b$name(?:uary|ruary|ch|il|e|y|ust|tember|ober|ember)?'
                  r'(?:\s+(20\d{2}))?\b')
              .firstMatch(text);
      if (match == null) continue;
      var year = int.tryParse(match.group(1) ?? '') ?? today.year;
      final month = index + 1;
      if (match.group(1) == null && month > today.month) year--;
      return _monthRange(DateTime(year, month));
    }
    final yearMatch = RegExp(r'\b(20\d{2})\b').firstMatch(text);
    if (yearMatch != null) return _yearRange(int.parse(yearMatch.group(1)!));
    return null;
  }

  static bool _isComparison(String text) => _containsAny(text, const [
        'month over month',
        'compare',
        'compared',
        'next to',
        'difference between',
        'up from last month',
        'down from last month',
        'versus',
        ' vs ',
        'higher than last month',
        'lower than last month',
        'increase from last month',
        'decrease from last month',
      ]);

  static (Map<String, Object?>, Map<String, Object?>) _comparisonRanges(
    String text,
    DateTime today,
  ) {
    final explicitMonths = _mentionedMonths(text, today);
    if (explicitMonths.length >= 2) {
      return (
        _monthRange(explicitMonths[0]),
        _monthRange(explicitMonths[1]),
      );
    }
    final quarters = _mentionedQuarters(text, today);
    if (quarters.length >= 2) {
      return (
        _quarterRange(quarters[0].$1, quarters[0].$2),
        _quarterRange(quarters[1].$1, quarters[1].$2),
      );
    }
    final years = RegExp(r'\b20\d{2}\b')
        .allMatches(text)
        .map((match) => int.parse(match.group(0)!))
        .toList(growable: false);
    if (years.length >= 2) {
      return (_yearRange(years[0]), _yearRange(years[1]));
    }
    if (_containsAny(text, const ['this year', 'current year']) &&
        _containsAny(text, const ['last year', 'previous year'])) {
      return (_yearRange(today.year), _yearRange(today.year - 1));
    }
    if (_containsAny(text, const ['this quarter', 'current quarter']) &&
        _containsPhrase(text, 'last quarter')) {
      final quarter = ((today.month - 1) ~/ 3) + 1;
      final previous =
          quarter == 1 ? (today.year - 1, 4) : (today.year, quarter - 1);
      return (
        _quarterRange(today.year, quarter),
        _quarterRange(previous.$1, previous.$2),
      );
    }
    final comparesPreviousPair =
        !_containsAny(text, const ['this month', 'current month']) &&
            _containsAny(text, const ['previous month', 'month before']);
    final current = comparesPreviousPair
        ? DateTime(today.year, today.month - 1)
        : DateTime(today.year, today.month);
    return (
      _monthRange(current),
      _monthRange(DateTime(current.year, current.month - 1)),
    );
  }

  static List<DateTime> _mentionedMonths(String text, DateTime today) {
    final mentions = <({int start, DateTime month})>[];
    for (var index = 0; index < _months.length; index++) {
      final name = _months[index];
      final matches = RegExp(
        '\\b$name(?:uary|ruary|ch|il|e|y|ust|tember|ober|ember)?'
        r'(?:\s+(20\d{2}))?\b',
      ).allMatches(text);
      for (final match in matches) {
        final month = index + 1;
        var year = int.tryParse(match.group(1) ?? '') ?? today.year;
        if (match.group(1) == null && month > today.month) year--;
        mentions.add((start: match.start, month: DateTime(year, month)));
      }
    }
    mentions.sort((left, right) => left.start.compareTo(right.start));
    return mentions.map((mention) => mention.month).toList(growable: false);
  }

  static List<(int, int)> _mentionedQuarters(String text, DateTime today) =>
      RegExp(r'\bq([1-4])(?:\s+(20\d{2}))?\b')
          .allMatches(text)
          .map(
            (match) => (
              int.tryParse(match.group(2) ?? '') ?? today.year,
              int.parse(match.group(1)!),
            ),
          )
          .toList(growable: false);

  static bool _looksLikeFinancialTotal(String text) =>
      _containsAny(text, const [
        'how much',
        'how many',
        'spend',
        'spent',
        'paid',
        'outflow',
        'outflows',
        'inflow',
        'inflows',
        'cash flow',
        'money movement',
        'payment',
        'payments',
        'expense',
        'expenses',
        'cost',
        'income',
        'earned',
        'received',
        'salary',
        'credited',
        'debited',
        'net',
        'saved',
        'balance change',
        'transactions',
        'debits',
        'credits',
        'came in',
        'cash gone',
        'earnings',
        'left over',
        'money went out',
        'went out',
      ]);

  static bool _hasUnsupportedAmountFilter(String text) {
    // Comparative words are also normal prose ("left over", "over the last
    // month"). Treat them as unsupported filters only when followed by a
    // numeric amount; normalization has already removed currency symbols.
    return RegExp(
      r'\b(?:above|below|over|under|more than|less than|greater than)\s+(?:rs\s*)?\d',
    ).hasMatch(text);
  }

  static bool _hasUnresolvedTimeReference(String text) =>
      _mentionsExplicitDateRange(text) ||
      _containsAny(text, const [
        'fiscal year',
      ]);

  static bool _mentionsExplicitDateRange(String text) =>
      RegExp(r'\b(?:from|between)\s+\d{1,4}').hasMatch(text);

  static bool _isClearlyUnsupported(String text) => _containsAny(text, const [
        'investment advice',
        'financial advice',
        'which stock',
        'what stock',
        'buy stocks',
        'sell stocks',
        'mutual fund recommendation',
        'loan recommendation',
        'credit card recommendation',
      ]);

  static Map<String, Object?>? _upcomingRange(String text, DateTime today) {
    final day = DateTime(today.year, today.month, today.day);
    if (_containsPhrase(text, 'this week')) {
      return _inclusiveRange(
        day,
        day.add(Duration(days: DateTime.daysPerWeek - day.weekday)),
      );
    }
    if (_containsPhrase(text, 'next week')) {
      final start =
          day.add(Duration(days: DateTime.daysPerWeek - day.weekday + 1));
      return _inclusiveRange(
        start,
        start.add(const Duration(days: DateTime.daysPerWeek - 1)),
      );
    }
    if (_containsAny(text, const ['this month', 'current month'])) {
      return _inclusiveRange(day, DateTime(day.year, day.month + 1, 0));
    }
    if (_containsPhrase(text, 'next month')) {
      final start = DateTime(day.year, day.month + 1);
      return _inclusiveRange(start, DateTime(day.year, day.month + 2, 0));
    }
    final daysMatch =
        RegExp(r'\b(?:next|coming)\s+(\d{1,3})\s+days?\b').firstMatch(text);
    if (daysMatch != null) {
      final days = int.parse(daysMatch.group(1)!);
      if (days >= 1 && days <= 366) {
        return _inclusiveRange(day, day.add(Duration(days: days)));
      }
    }
    return null;
  }

  static Map<String, Object?> _inclusiveRange(DateTime start, DateTime end) => {
        'kind': 'range',
        'start': _date(start),
        'end': _date(end),
      };

  static String? _merchant(String original) {
    final activityMatch = RegExp(
      r'^\s*(?:show|list)(?:\s+me)?\s+(.+?)\s+(?:activity|transactions|payments)\b',
      caseSensitive: false,
    ).firstMatch(original);
    final directPayMatch = RegExp(
      r'\b(?:pay|paid)\s+(?!at\b|to\b|in\b)(.+?)(?=\s+(?:today|yesterday|this|last|previous|current|in|during|for|over|between|from)\b|[?.!,]|$)',
      caseSensitive: false,
    ).firstMatch(original.trim());
    final prepositionMatch = RegExp(
      r'\b(?:at|to|from|with|on)\s+(.+?)(?=\s+(?:this|last|in|during|for|over|between|from)\b|[?.!,]|$)',
      caseSensitive: false,
    ).firstMatch(original.trim());
    final merchant =
        (activityMatch ?? directPayMatch ?? prepositionMatch)?.group(1)?.trim();
    final normalizedMerchant = _normalize(merchant ?? '');
    if (merchant == null ||
        merchant.isEmpty ||
        merchant.split(' ').length > 6 ||
        RegExp(
          r'^(?:all|my|recent|latest|debit|credit|cash|spending|expenses?|income)(?:\s|$)',
        ).hasMatch(normalizedMerchant) ||
        _looksTemporal(merchant)) {
      return null;
    }
    return merchant;
  }

  static bool _looksTemporal(String value) {
    final normalized = _normalize(value);
    return RegExp(r'^\d').hasMatch(normalized) ||
        RegExp(r'^date(?:\s|$)').hasMatch(normalized) ||
        RegExp(
          r'^(?:the\s+)?(?:today|yesterday|this|last|past|previous|next|current|recent)\b',
        ).hasMatch(normalized) ||
        _months.any(
          (month) => RegExp('^$month[a-z]*(?:\\s|\$)').hasMatch(normalized),
        );
  }

  static Map<String, Object?> _monthRange(DateTime value) => {
        'kind': 'month',
        'month': '${value.year.toString().padLeft(4, '0')}-'
            '${value.month.toString().padLeft(2, '0')}',
      };

  static Map<String, Object?> _yearRange(int year) => _inclusiveRange(
        DateTime(year),
        DateTime(year, 12, 31),
      );

  static Map<String, Object?> _quarterRange(int year, int quarter) {
    final start = DateTime(year, (quarter - 1) * 3 + 1);
    return _inclusiveRange(start, DateTime(year, start.month + 3, 0));
  }

  static Map<String, Object?>? _explicitDateRange(String text) {
    final iso = RegExp(
      r'\b(?:from|between)\s+(20\d{2})-(\d{1,2})-(\d{1,2})\s+(?:to|and)\s+(20\d{2})-(\d{1,2})-(\d{1,2})\b',
    ).firstMatch(text);
    if (iso != null) {
      final start = _validDate(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
      final end = _validDate(
        int.parse(iso.group(4)!),
        int.parse(iso.group(5)!),
        int.parse(iso.group(6)!),
      );
      if (start != null && end != null && !end.isBefore(start)) {
        return _inclusiveRange(start, end);
      }
    }

    final monthPattern = _months.join('|');
    final natural = RegExp(
      '\\b(?:from|between)\\s+(\\d{1,2})\\s+($monthPattern)[a-z]*\\s+(20\\d{2})'
      '\\s+(?:to|and)\\s+(\\d{1,2})\\s+($monthPattern)[a-z]*\\s+(20\\d{2})\\b',
    ).firstMatch(text);
    if (natural == null) return null;
    final start = _validDate(
      int.parse(natural.group(3)!),
      _months.indexOf(natural.group(2)!) + 1,
      int.parse(natural.group(1)!),
    );
    final end = _validDate(
      int.parse(natural.group(6)!),
      _months.indexOf(natural.group(5)!) + 1,
      int.parse(natural.group(4)!),
    );
    if (start == null || end == null || end.isBefore(start)) return null;
    return _inclusiveRange(start, end);
  }

  static DateTime? _validDate(int year, int month, int day) {
    final value = DateTime(year, month, day);
    return value.year == year && value.month == month && value.day == day
        ? value
        : null;
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static bool _containsAny(String text, Iterable<String> values) =>
      values.any(text.contains);

  /// Resolves a category filter from [normalized], tolerating single-token
  /// references like "food" for "Food & Dining".
  ///
  /// A full normalized-name phrase match always wins (longest on ties). Failing
  /// that, a single distinctive token is accepted only when it belongs to
  /// exactly one category, so shared/ambiguous words (e.g. "food" when both
  /// "Food & Dining" and "Fast Food" exist) fail closed rather than guessing.
  static String? _matchCategory(
    String normalized,
    Iterable<String> categoryNames,
  ) {
    final names = categoryNames.toList(growable: false);
    final full = names
        .where((name) => _containsPhrase(normalized, _normalize(name)))
        .fold<String?>(
          null,
          (best, name) =>
              best == null || name.length > best.length ? name : best,
        );
    if (full != null) return full;

    final tokenOwners = <String, Set<String>>{};
    for (final name in names) {
      for (final token in _categoryTokens(name)) {
        (tokenOwners[token] ??= <String>{}).add(name);
      }
    }
    String? matched;
    for (final entry in tokenOwners.entries) {
      if (entry.value.length != 1) continue; // token shared across categories
      if (!_containsPhrase(normalized, entry.key)) continue;
      final owner = entry.value.first;
      // Tokens from two different categories in one question are ambiguous.
      if (matched != null && matched != owner) return null;
      matched = owner;
    }
    return matched;
  }

  /// Distinctive, matchable tokens of a category name: normalized words of at
  /// least three letters that are not pure connectors or generic buckets.
  static Iterable<String> _categoryTokens(String name) sync* {
    const stopwords = {
      'and',
      'the',
      'for',
      'misc',
      'other',
      'others',
      'general',
      'expense',
      'expenses',
    };
    for (final token in _normalize(name).split(' ')) {
      if (token.length < 3) continue;
      if (int.tryParse(token) != null) continue;
      if (stopwords.contains(token)) continue;
      yield token;
    }
  }

  static bool _containsPhrase(String text, String phrase) =>
      RegExp('(^|\\s)${RegExp.escape(phrase)}(?=\\s|\$)').hasMatch(text);

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s-]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static const _months = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];
}

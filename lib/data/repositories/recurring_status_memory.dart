import 'dart:convert';

import '../db/database.dart';
import '../models/source_currency.dart';

/// Keeps user-controlled recurring statuses stable when a detector rebuild
/// changes a series ID or temporarily cannot detect the series.
abstract final class RecurringStatusMemory {
  static const _key = 'user_recurring_statuses_v1';

  static bool isUserControlled(String status) =>
      status == 'paused' || status == 'cancelled' || status == 'muted';

  static String identity(RecurringSery series) {
    final currency = SourceCurrency(
      code: series.currencyCode,
      symbol: series.currencySymbol,
    );
    final currencyIdentity =
        series.currencyCode == null && series.currencySymbol == null
            ? ''
            : '${currency.bucketKey}|';
    return '${series.merchantId}|${series.kind}|$currencyIdentity'
        '${series.period}|${series.periodDays}|'
        '${series.expectedAmount.toStringAsFixed(0)}';
  }

  static Future<Map<String, String>> read(AppDatabase database) async {
    final row = await (database.select(database.modelMeta)
          ..where((entry) => entry.key.equals(_key)))
        .getSingleOrNull();
    if (row == null) return {};
    try {
      final decoded = jsonDecode(row.value);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } on FormatException {
      return {};
    }
  }

  static Future<void> set(
    AppDatabase database, {
    required RecurringSery series,
    required String status,
  }) =>
      remember(database, identity(series), status);

  static Future<void> remember(
    AppDatabase database,
    String key,
    String status,
  ) async {
    final statuses = await read(database);
    if (isUserControlled(status)) {
      statuses[key] = status;
    } else {
      statuses.remove(key);
    }
    if (statuses.isEmpty) {
      await (database.delete(database.modelMeta)
            ..where((row) => row.key.equals(_key)))
          .go();
      return;
    }
    await database.into(database.modelMeta).insertOnConflictUpdate(
          ModelMetaCompanion.insert(key: _key, value: jsonEncode(statuses)),
        );
  }
}

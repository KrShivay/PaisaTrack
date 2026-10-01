import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/recurring_status_memory.dart';

void main() {
  RecurringSery series({
    String? code,
    String? symbol,
    double expectedAmount = 100,
  }) =>
      RecurringSery(
        id: 'series',
        merchantId: 'merchant',
        label: 'Service',
        expectedAmount: expectedAmount,
        currencyCode: code,
        currencySymbol: symbol,
        tolerancePct: 0.05,
        period: 'monthly',
        periodDays: 30,
        nextExpectedDate: DateTime.utc(2026, 10, 1),
        lastAmount: 100,
        amountTrend: 'flat',
        occurrences: 3,
        status: 'active',
        kind: 'subscription',
      );

  test('identity retains the v1 period and rounded amount bucket', () {
    expect(
      RecurringStatusMemory.identity(series()),
      'merchant|subscription|monthly|30|100',
    );
    expect(
      RecurringStatusMemory.identity(series(expectedAmount: 250)),
      isNot(RecurringStatusMemory.identity(series())),
    );
  });

  test('same merchant amount buckets keep separate remembered statuses',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    final lower = series(expectedAmount: 299);
    final higher = series(expectedAmount: 599);
    await RecurringStatusMemory.remember(
      database,
      RecurringStatusMemory.identity(lower),
      'paused',
    );
    await RecurringStatusMemory.remember(
      database,
      RecurringStatusMemory.identity(higher),
      'cancelled',
    );
    final statuses = await RecurringStatusMemory.read(database);
    expect(statuses, hasLength(2));
    expect(statuses[RecurringStatusMemory.identity(lower)], 'paused');
    expect(statuses[RecurringStatusMemory.identity(higher)], 'cancelled');
  });

  test('reads existing v1 amount bucket entries', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    const key = 'user_recurring_statuses_v1';
    final seriesKey = RecurringStatusMemory.identity(series());
    await database.into(database.modelMeta).insert(
          ModelMetaCompanion.insert(
            key: key,
            value: jsonEncode({seriesKey: 'paused'}),
          ),
        );

    expect(await RecurringStatusMemory.read(database), {seriesKey: 'paused'});
  });

  test('known and bare-symbol series receive separate identities', () {
    final usd =
        RecurringStatusMemory.identity(series(code: 'USD', symbol: r'$'));
    final dollar = RecurringStatusMemory.identity(series(symbol: r'$'));
    expect(usd, isNot(dollar));
    expect(usd, contains('USD'));
    expect(dollar, contains(r'$'));
  });

  test('known ISO identity does not fragment on a missing source symbol', () {
    expect(
      RecurringStatusMemory.identity(series(code: 'USD', symbol: r'$')),
      RecurringStatusMemory.identity(series(code: 'USD')),
    );
  });
}

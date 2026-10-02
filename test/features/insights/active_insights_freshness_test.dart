import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/clock.dart';
import 'package:paisatrack/core/financial_calendar.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/insights/insights_screen.dart';

void main() {
  test('legacy insights remain hidden while the freshness stamp is missing',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    const calendar = FinancialCalendar.fixed(Duration.zero);
    final now = DateTime.utc(2026, 7, 10, 12);
    final period = calendar.monthKey(now);
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn',
            ts: now.millisecondsSinceEpoch,
            amount: 300,
            direction: 'debit',
            channel: 'test',
            parseSource: 'test',
            confidenceJson: '{}',
            status: 'confirmed',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database.into(database.insights).insert(
          InsightsCompanion.insert(
            id: 'fees_total:$period',
            period: period,
            kind: 'fees_total',
            payloadJson: '{}',
          ),
        );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => database),
        clockProvider.overrideWith((ref) => () => now),
        financialCalendarProvider.overrideWith((ref) => calendar),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    final initial = Completer<void>();
    final subscription =
        container.listen(activeInsightsProvider, (previous, next) {
      if (next.valueOrNull != null && !initial.isCompleted) {
        initial.complete();
      }
    });
    addTearDown(subscription.close);
    await initial.future.timeout(const Duration(seconds: 2));
    expect(container.read(activeInsightsProvider).valueOrNull, isEmpty);
  });
}

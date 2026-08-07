import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/recurring_repository.dart';

void main() {
  late AppDatabase database;
  late RecurringRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = RecurringRepository(database);

    // Seed a merchant (foreign-key requirement for recurring series).
    final now = DateTime.utc(2026, 7, 1);
    await database.into(database.merchants).insert(
          MerchantsCompanion.insert(
            id: 'm_bsnl',
            canonicalName: 'BSNL',
            firstSeen: now,
            lastSeen: now,
          ),
        );
    await database.into(database.recurringSeries).insert(
          RecurringSeriesCompanion.insert(
            id: 'rec_bsnl',
            merchantId: 'm_bsnl',
            label: 'BSNL Broadband',
            expectedAmount: 499.0,
            tolerancePct: 0.05,
            period: 'monthly',
            periodDays: 30,
            nextExpectedDate: DateTime.utc(2026, 8, 1),
            lastAmount: 499.0,
            amountTrend: 'flat',
            occurrences: 6,
            status: 'active',
            kind: 'bill',
          ),
        );
  });

  tearDown(() async {
    await database.close();
  });

  Future<RecurringSery> fetchSeries() =>
      (database.select(database.recurringSeries)
            ..where((r) => r.id.equals('rec_bsnl')))
          .getSingle();

  test('setStatus changes active → cancelled', () async {
    await repository.setStatus(seriesId: 'rec_bsnl', status: 'cancelled');
    final row = await fetchSeries();
    expect(row.status, equals('cancelled'));
  });

  test('setStatus changes cancelled → active (reactivate)', () async {
    await repository.setStatus(seriesId: 'rec_bsnl', status: 'cancelled');
    await repository.setStatus(seriesId: 'rec_bsnl', status: 'active');
    final row = await fetchSeries();
    expect(row.status, equals('active'));
  });

  test('setStatus on unknown id is a no-op and does not throw', () async {
    await expectLater(
      repository.setStatus(seriesId: 'nonexistent', status: 'cancelled'),
      completes,
    );
    final row = await fetchSeries();
    expect(row.status, equals('active'));
  });
}

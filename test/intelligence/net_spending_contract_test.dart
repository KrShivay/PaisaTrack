import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/util/money_utils.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';
import 'package:paisatrack/intelligence/burn_rate_forecaster.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('MoneyUtils converts between rupees and paise accurately', () {
    expect(MoneyUtils.toPaise(150.75), 15075);
    expect(MoneyUtils.toRupees(15075), 150.75);
    expect(MoneyUtils.toPaise(0.0), 0);
    expect(MoneyUtils.toRupees(0), 0.0);
  });

  test('Dashboard and burn rate forecaster aggregates match expectations', () async {
    final ts = DateTime.utc(2026, 7, 10, 10, 0).millisecondsSinceEpoch;

    // Settled transaction
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_1',
            ts: ts,
            amount: 1500.0,
            direction: 'debit',
            channel: 'upi',
            parseSource: 'generic',
            confidenceJson: '{}',
            status: 'auto',
            lifecycleState: const Value('settled'),
            createdAt: DateTime.utc(2026, 7, 10),
            updatedAt: DateTime.utc(2026, 7, 10),
          ),
        );

    final dashboardRepo = DashboardRepository(database);
    final snapshot = await dashboardRepo.load(
      DashboardQueryWindow(
        start: DateTime.utc(2026, 7, 1),
        end: DateTime.utc(2026, 7, 31),
        trendStart: DateTime.utc(2026, 7, 1),
        trendEnd: DateTime.utc(2026, 7, 31),
        previousStart: DateTime.utc(2026, 6, 1),
        previousEnd: DateTime.utc(2026, 6, 30),
      ),
    );

    expect(snapshot.debitTotal, 1500.0);

    final forecaster = BurnRateForecaster(database);
    final forecast = await forecaster.run(today: DateTime.utc(2026, 7, 10));

    expect(forecast.currentSpend, 1500.0);
  });
}

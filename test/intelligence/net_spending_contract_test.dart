import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/financial_calendar.dart';
import 'package:paisatrack/core/util/money_utils.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';
import 'package:paisatrack/intelligence/assistant/assistant_intent.dart';
import 'package:paisatrack/intelligence/assistant/query_engine.dart';
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

  test('Dashboard and burn rate forecaster aggregates match expectations',
      () async {
    final ts = DateTime.utc(2026, 7, 10, 10, 0).millisecondsSinceEpoch;

    // Settled transaction
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_1',
            ts: ts,
            amount: 1500.0,
            currencyCode: const Value('INR'),
            currencySymbol: const Value('₹'),
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

    final forecaster = BurnRateForecaster(
      database,
      calendar: const FinancialCalendar.fixed(Duration.zero),
    );
    final forecast = await forecaster.run(today: DateTime.utc(2026, 7, 10));

    expect(forecast.currentSpend, 1500.0);
  });

  test('assistant spend and net match Dashboard eligibility', () async {
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: 'transfers',
            name: 'Transfers',
            icon: 'swap',
            isSpending: false,
            sortOrder: 1,
            isUserCreated: false,
          ),
        );
    final date = DateTime.utc(2026, 7, 10);
    Future<void> addTxn(
      String id,
      double amount, {
      String direction = 'debit',
      String? categoryId,
    }) =>
        database.into(database.transactions).insert(
              TransactionsCompanion.insert(
                id: id,
                ts: date.millisecondsSinceEpoch,
                amount: amount,
                currencyCode: const Value('INR'),
                currencySymbol: const Value('₹'),
                direction: direction,
                channel: 'upi',
                categoryId: Value(categoryId),
                parseSource: 'test',
                confidenceJson: '{}',
                status: 'auto',
                createdAt: date,
                updatedAt: date,
              ),
            );

    await addTxn('spending', 150);
    await addTxn('transfer', 80, categoryId: 'transfers');
    await addTxn('income', 500, direction: 'credit');

    final window = DashboardQueryWindow(
      start: DateTime.utc(2026, 7, 1),
      end: DateTime.utc(2026, 8, 1),
      trendStart: DateTime.utc(2026, 7, 1),
      trendEnd: DateTime.utc(2026, 8, 1),
      previousStart: DateTime.utc(2026, 6, 1),
      previousEnd: DateTime.utc(2026, 7, 1),
    );
    final dashboard = await DashboardRepository(database).load(window);
    final assistant = AssistantQueryEngine(database);
    final range = AssistantTimeRange(window.start, window.end, label: 'July');
    Future<TotalQueryResult> total(AssistantMetric metric) async =>
        await assistant.run(
          AssistantIntent(
            kind: AssistantIntentKind.periodTotal,
            metric: metric,
            aggregation: AssistantAggregation.sum,
            range: range,
          ),
        ) as TotalQueryResult;

    final spend = await total(AssistantMetric.spend);
    final net = await total(AssistantMetric.net);
    final dashboardNet = dashboard.creditTotal - dashboard.debitTotal;

    expect(spend.value, dashboard.debitTotal);
    expect(spend.value, 150);
    expect(net.value, dashboardNet);
    expect(net.value, 350);
  });
}

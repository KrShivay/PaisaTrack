import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.seedDefaultCategories();
  });

  tearDown(() => database.close());

  Future<void> insert(
    String id,
    DateTime timestamp,
    double amount, {
    String direction = 'debit',
    String? categoryId = 'food_dining',
    bool analyticsExcluded = false,
    String? ownedTransferId,
    String? currencyCode = 'INR',
    String? currencySymbol = '₹',
  }) {
    return database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            ts: timestamp.millisecondsSinceEpoch,
            amount: amount,
            currencyCode: Value(currencyCode),
            currencySymbol: Value(currencySymbol),
            direction: direction,
            channel: 'upi',
            categoryId: Value(categoryId),
            merchantRaw: const Value('TEST MERCHANT'),
            parseSource: 'manual',
            confidenceJson: '{}',
            status: 'confirmed',
            isAnalyticsExcluded: Value(analyticsExcluded),
            ownedTransferId: Value(ownedTransferId),
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        );
  }

  test('dashboard SQL aggregates preserve analytics inclusion semantics',
      () async {
    await insert('current_debit', DateTime(2026, 7, 10), 100);
    await insert(
      'foreign_debit',
      DateTime(2026, 7, 10),
      250,
      currencyCode: 'USD',
      currencySymbol: r'$',
    );
    await insert(
      'bare_dollar_debit',
      DateTime(2026, 7, 10),
      80,
      currencyCode: null,
      currencySymbol: r'$',
    );
    await insert(
      'unknown_debit',
      DateTime(2026, 7, 10),
      33,
      currencyCode: null,
      currencySymbol: null,
    );
    await insert(
      'current_credit',
      DateTime(2026, 7, 11),
      500,
      direction: 'credit',
      categoryId: 'income',
    );
    await insert('previous_debit', DateTime(2026, 6, 10), 50);
    await insert(
      'transfer',
      DateTime(2026, 7, 12),
      1000,
      categoryId: 'transfers',
    );
    await insert(
      'excluded',
      DateTime(2026, 7, 13),
      900,
      analyticsExcluded: true,
    );
    await insert(
      'owned_transfer',
      DateTime(2026, 7, 14),
      800,
      ownedTransferId: 'pair_1',
    );

    final snapshot = await DashboardRepository(database).load(
      DashboardQueryWindow(
        start: DateTime(2026, 7),
        end: DateTime(2026, 8),
        previousStart: DateTime(2026, 6),
        previousEnd: DateTime(2026, 7),
        trendStart: DateTime(2026, 2),
        trendEnd: DateTime(2026, 8),
      ),
    );

    expect(snapshot.debitTotal, 100);
    expect(snapshot.creditTotal, 500);
    expect(snapshot.previousSpend, 50);
    expect(snapshot.categories.single.total, 100);
    expect(snapshot.merchants.single.total, 100);
    expect(snapshot.merchants.single.count, 1);
    expect(snapshot.trendByMonth['2026-06'], 50);
    expect(snapshot.trendByMonth['2026-07'], 100);
    // Completeness: spending debit removed by exclusion flags (analytics-excluded
    // 900 + owned-transfer 800). The non-spending 'transfers' debit is excluded
    // by category, not a flag, so it is not part of this figure.
    expect(snapshot.excludedDebitTotal, 1700);
    expect(snapshot.excludedDebitCount, 2);
    final currencies = {
      for (final aggregate in snapshot.currencyTotals)
        '${aggregate.currencyCode ?? ''}|${aggregate.currencySymbol ?? ''}':
            aggregate.debitTotal,
    };
    expect(currencies['USD|\$'], 250);
    expect(currencies['|\$'], 80);
    expect(currencies['|'], 33);
  });

  test('T-198 top merchants: readable VPA names, no repeated Unknown rows',
      () async {
    Future<void> debit(
      String id,
      double amount, {
      String? merchantRaw,
      String? vpa,
      String categoryId = 'food_dining',
    }) {
      final ts = DateTime(2026, 7, 10);
      return database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: id,
              ts: ts.millisecondsSinceEpoch,
              amount: amount,
              currencyCode: const Value('INR'),
              direction: 'debit',
              channel: 'upi',
              categoryId: Value(categoryId),
              merchantRaw: Value(merchantRaw),
              counterpartyVpa: Value(vpa),
              parseSource: 'template',
              confidenceJson: '{}',
              status: 'confirmed',
              createdAt: ts,
              updatedAt: ts,
            ),
          );
    }

    // No payee at all: a personal-loan EMI and a SIP debit.
    await debit('loan', 9000, categoryId: 'emi_personal_loan');
    await debit('sip', 5000, categoryId: 'investments_mutual_fund_sip');
    await debit('sip_2', 1000, categoryId: 'investments_mutual_fund_sip');
    // A blank payee from an empty correction groups by category too.
    await debit('blank', 50, merchantRaw: '', categoryId: 'emi_personal_loan');
    await debit('zomato_1', 400, vpa: 'payzomato@hdfcbank');
    await debit(
      'zomato_2',
      300,
      merchantRaw: 'zomato.eternaltsp.payu@hdfcbank',
      vpa: 'zomato.eternaltsp.payu@hdfcbank',
    );

    final snapshot = await DashboardRepository(database).load(
      DashboardQueryWindow(
        start: DateTime(2026, 7),
        end: DateTime(2026, 8),
        previousStart: DateTime(2026, 6),
        previousEnd: DateTime(2026, 7),
        trendStart: DateTime(2026, 2),
        trendEnd: DateTime(2026, 8),
      ),
    );

    final names = snapshot.merchants.map((row) => row.name).toList();
    expect(names.toSet(), hasLength(names.length));
    expect(names, isNot(contains('Unknown')));
    final byName = {for (final row in snapshot.merchants) row.name: row};
    expect(byName['Unnamed · Personal Loan']!.total, 9050);
    expect(byName['Unnamed · Mutual Fund SIP']!.total, 6000);
    expect(byName['Unnamed · Mutual Fund SIP']!.count, 2);
    // Two Zomato VPAs are separate payees until the user links them: no
    // silent merge, and the shared title is told apart by the VPA.
    expect(byName['Zomato · payzomato@hdfcbank']!.total, 400);
    expect(byName['Zomato · zomato.eternaltsp.payu@hdfcbank']!.total, 300);
  });

  test('trend buckets honour the injected timezone offset', () async {
    // 2026-06-30 20:00 UTC is 2026-07-01 01:30 in IST (+5:30).
    await insert('boundary', DateTime.utc(2026, 6, 30, 20), 300);

    DashboardQueryWindow window({Duration offset = Duration.zero}) =>
        DashboardQueryWindow(
          start: DateTime.utc(2026, 6),
          end: DateTime.utc(2026, 8),
          previousStart: DateTime.utc(2026, 5),
          previousEnd: DateTime.utc(2026, 6),
          trendStart: DateTime.utc(2026, 2),
          trendEnd: DateTime.utc(2026, 8),
          timeZoneOffset: offset,
        );

    final utc = await DashboardRepository(database).load(window());
    expect(utc.trendByMonth['2026-06'], 300);
    expect(utc.trendByMonth.containsKey('2026-07'), isFalse);

    final ist = await DashboardRepository(database).load(
      window(offset: const Duration(hours: 5, minutes: 30)),
    );
    expect(ist.trendByMonth['2026-07'], 300);
    expect(ist.trendByMonth.containsKey('2026-06'), isFalse);
  });

  test('dashboard excludes non-settled debits from every spending aggregate',
      () async {
    await insert('settled', DateTime(2026, 7, 10), 100);
    await insert('pending', DateTime(2026, 7, 11), 900);
    await (database.update(database.transactions)
          ..where((row) => row.id.equals('pending')))
        .write(const TransactionsCompanion(lifecycleState: Value('pending')));

    final snapshot = await DashboardRepository(database).load(
      DashboardQueryWindow(
        start: DateTime(2026, 7),
        end: DateTime(2026, 8),
        previousStart: DateTime(2026, 6),
        previousEnd: DateTime(2026, 7),
        trendStart: DateTime(2026, 2),
        trendEnd: DateTime(2026, 8),
      ),
    );

    expect(snapshot.debitTotal, 100);
    expect(snapshot.categories.single.total, 100);
    expect(snapshot.merchants.single.total, 100);
    expect(snapshot.trendByMonth['2026-07'], 100);
  });

  test('transaction feed enforces limit and optional date bounds', () async {
    for (var day = 1; day <= 5; day++) {
      await insert('txn_$day', DateTime(2026, 7, day), day.toDouble());
    }

    final items = await TransactionRepository(database)
        .watchTransactions(
          limit: 2,
          start: DateTime(2026, 7, 2),
          end: DateTime(2026, 7, 5),
        )
        .first;

    expect(items.map((item) => item.id), ['txn_4', 'txn_3']);
  });
}

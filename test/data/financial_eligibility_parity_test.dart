import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/analytics/financial_eligibility.dart';
import 'package:paisatrack/data/db/database.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: 'non-spending',
            name: 'Transfer',
            icon: 'swap',
            isSpending: false,
            sortOrder: 1,
            isUserCreated: false,
          ),
        );
    await database.customStatement('PRAGMA foreign_keys = OFF');

    final cases = [
      (
        id: 'eligible',
        category: null,
        state: 'settled',
        deleted: false,
        notTxn: false,
        duplicate: false,
        excluded: false,
        transfer: false,
        direction: 'debit'
      ),
      (
        id: 'deleted',
        category: null,
        state: 'settled',
        deleted: true,
        notTxn: false,
        duplicate: false,
        excluded: false,
        transfer: false,
        direction: 'debit'
      ),
      (
        id: 'not-transaction',
        category: null,
        state: 'settled',
        deleted: false,
        notTxn: true,
        duplicate: false,
        excluded: false,
        transfer: false,
        direction: 'debit'
      ),
      (
        id: 'duplicate',
        category: null,
        state: 'settled',
        deleted: false,
        notTxn: false,
        duplicate: true,
        excluded: false,
        transfer: false,
        direction: 'debit'
      ),
      (
        id: 'analytics-excluded',
        category: null,
        state: 'settled',
        deleted: false,
        notTxn: false,
        duplicate: false,
        excluded: true,
        transfer: false,
        direction: 'debit'
      ),
      (
        id: 'owned-transfer',
        category: null,
        state: 'settled',
        deleted: false,
        notTxn: false,
        duplicate: false,
        excluded: false,
        transfer: true,
        direction: 'debit'
      ),
      (
        id: 'pending',
        category: null,
        state: 'pending',
        deleted: false,
        notTxn: false,
        duplicate: false,
        excluded: false,
        transfer: false,
        direction: 'debit'
      ),
      (
        id: 'failed',
        category: null,
        state: 'failed',
        deleted: false,
        notTxn: false,
        duplicate: false,
        excluded: false,
        transfer: false,
        direction: 'debit'
      ),
      (
        id: 'reversed',
        category: null,
        state: 'reversed',
        deleted: false,
        notTxn: false,
        duplicate: false,
        excluded: false,
        transfer: false,
        direction: 'debit'
      ),
      (
        id: 'credit',
        category: null,
        state: 'settled',
        deleted: false,
        notTxn: false,
        duplicate: false,
        excluded: false,
        transfer: false,
        direction: 'credit'
      ),
      (
        id: 'non-spending-category',
        category: 'non-spending',
        state: 'settled',
        deleted: false,
        notTxn: false,
        duplicate: false,
        excluded: false,
        transfer: false,
        direction: 'debit'
      ),
      (
        id: 'missing-category',
        category: 'missing',
        state: 'settled',
        deleted: false,
        notTxn: false,
        duplicate: false,
        excluded: false,
        transfer: false,
        direction: 'debit'
      ),
      (
        id: 'null-category',
        category: null,
        state: 'settled',
        deleted: false,
        notTxn: false,
        duplicate: false,
        excluded: false,
        transfer: false,
        direction: 'debit'
      ),
    ];
    for (final row in cases) {
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: row.id,
              ts: 1,
              amount: 1,
              direction: row.direction,
              channel: 'test',
              categoryId: Value(row.category),
              parseSource: 'test',
              confidenceJson: '{}',
              status: 'auto',
              isDeleted: Value(row.deleted),
              isNotTransaction: Value(row.notTxn),
              duplicateOfTxnId: Value(row.duplicate ? 'eligible' : null),
              isAnalyticsExcluded: Value(row.excluded),
              ownedTransferId: Value(row.transfer ? 'owned' : null),
              lifecycleState: Value(row.state),
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
          );
    }
  });

  tearDown(() async => database.close());

  test('SQL, Drift, and row helper agree across eligibility edge cases',
      () async {
    final sqlRows = await database.customSelect(
      '''
SELECT t.id, ${FinancialEligibility.spendingDebitSql} AS eligible
FROM transactions t
LEFT JOIN categories c ON c.id = t.category_id
''',
      readsFrom: {database.transactions, database.categories},
    ).get();
    final sql = {
      for (final row in sqlRows)
        row.read<String>('id'): row.read<bool>('eligible'),
    };
    final driftRows = await (database.select(database.transactions)
          ..where(
            (t) => FinancialEligibility.spendingDebit(t, database.categories),
          ))
        .get();
    final drift = driftRows.map((row) => row.id).toSet();
    final allRows = await database.select(database.transactions).get();
    const expected = {
      'eligible',
      'missing-category',
      'null-category',
    };
    final helper = {
      for (final row in allRows)
        if (FinancialEligibility.includesSpendingDebit(
          row,
          categoryIsSpending: row.categoryId != 'non-spending',
        ))
          row.id,
    };

    expect(
      sql.values.where((eligible) => eligible),
      hasLength(expected.length),
    );
    expect(
      sql.entries
          .where((entry) => entry.value)
          .map((entry) => entry.key)
          .toSet(),
      expected,
    );
    expect(drift, expected);
    expect(helper, expected);
  });

  test('base SQL and Drift agree for settled credits', () async {
    final sqlRows = await database.customSelect(
      '''
SELECT t.id, ${FinancialEligibility.baseSql} AS eligible
FROM transactions t
''',
      readsFrom: {database.transactions},
    ).get();
    final sql = {
      for (final row in sqlRows)
        if (row.read<bool>('eligible')) row.read<String>('id'),
    };
    final drift = (await (database.select(database.transactions)
              ..where(FinancialEligibility.base))
            .get())
        .map((row) => row.id)
        .toSet();

    expect(sql, contains('credit'));
    expect(drift, contains('credit'));
    expect(drift, sql);
  });
}

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/analytics/financial_eligibility.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';
import 'package:paisatrack/data/repositories/payment_source_repository.dart';

void main() {
  late AppDatabase database;
  late PaymentSourceRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = PaymentSourceRepository(database);
    await database.customSelect('SELECT 1').get();
  });

  tearDown(() => database.close());

  // Owned-transfer reconciliation requires distinct known four-digit account
  // suffixes, so every fixture source gets a unique numeric suffix.
  var nextAccountSuffix = 1000;

  Future<void> addSources(Iterable<String> ids) async {
    final now = DateTime.utc(2026, 1, 1);
    for (final id in ids) {
      final suffix = nextAccountSuffix++;
      await database.into(database.paymentSources).insert(
            PaymentSourcesCompanion.insert(
              id: id,
              kind: 'bank',
              maskedIdentifier: 'XX$suffix',
              isOwned: const Value(true),
              isActive: const Value(true),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
  }

  Future<void> addTransaction({
    required String id,
    required String sourceId,
    required String direction,
    required int ts,
    double amount = 500,
    String? currencyCode,
    String? currencySymbol,
    bool isNotTransaction = false,
    String lifecycleState = 'settled',
  }) async {
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            ts: ts,
            amount: amount,
            currencyCode: Value(currencyCode),
            currencySymbol: Value(currencySymbol),
            direction: direction,
            channel: 'upi',
            paymentSourceId: Value(sourceId),
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'confirmed',
            lifecycleState: Value(lifecycleState),
            isNotTransaction: Value(isNotTransaction),
            createdAt: DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true),
          ),
        );
  }

  Future<List<Transaction>> transactions() =>
      database.select(database.transactions).get();

  Future<List<TransactionLink>> links() =>
      database.select(database.transactionLinks).get();

  test('uses reciprocal singleton matches across same-date source pairs',
      () async {
    const day = 1767225600000;
    await addSources(['src_a', 'src_b', 'src_c', 'src_d']);
    await addTransaction(
      id: 'debit_a',
      sourceId: 'src_a',
      direction: 'debit',
      ts: day,
    );
    await addTransaction(
      id: 'credit_b',
      sourceId: 'src_b',
      direction: 'credit',
      ts: day + 600000,
    );
    await addTransaction(
      id: 'debit_c',
      sourceId: 'src_c',
      direction: 'debit',
      ts: day + 7200000,
    );
    await addTransaction(
      id: 'credit_d',
      sourceId: 'src_d',
      direction: 'credit',
      ts: day + 7800000,
    );

    expect(
      await repository.reconcileOwnedTransfers(clock: () => DateTime.utc(2026)),
      2,
    );
    final rows = await transactions();
    expect(rows.every((row) => row.ownedTransferId != null), isTrue);
    expect(rows.map((row) => row.ownedTransferId).toSet(), hasLength(2));
    expect(await links(), hasLength(2));
  });

  test('leaves two debits competing for one credit completely unlinked',
      () async {
    const ts = 1767225600000;
    await addSources(['src_a', 'src_b', 'src_c']);
    await addTransaction(
      id: 'debit_a',
      sourceId: 'src_a',
      direction: 'debit',
      ts: ts,
    );
    await addTransaction(
      id: 'debit_b',
      sourceId: 'src_b',
      direction: 'debit',
      ts: ts + 1000,
    );
    await addTransaction(
      id: 'credit_c',
      sourceId: 'src_c',
      direction: 'credit',
      ts: ts + 2000,
    );

    expect(await repository.reconcileOwnedTransfers(), 0);
    expect(
      (await transactions()).every((row) => row.ownedTransferId == null),
      isTrue,
    );
    expect(await links(), isEmpty);
  });

  test('matches both inclusive window boundaries but rejects one ms outside',
      () async {
    const ts = 1767225600000;
    await addSources(['src_a', 'src_b', 'src_c', 'src_d', 'src_e', 'src_f']);
    await addTransaction(
      id: 'debit_before',
      sourceId: 'src_a',
      direction: 'debit',
      ts: ts,
    );
    await addTransaction(
      id: 'credit_at_plus_boundary',
      sourceId: 'src_b',
      direction: 'credit',
      ts: ts + 600000,
    );
    await addTransaction(
      id: 'debit_after',
      sourceId: 'src_c',
      direction: 'debit',
      ts: ts + 7200000,
    );
    await addTransaction(
      id: 'credit_at_minus_boundary',
      sourceId: 'src_d',
      direction: 'credit',
      ts: ts + 6600000,
    );
    await addTransaction(
      id: 'debit_outside',
      sourceId: 'src_e',
      direction: 'debit',
      ts: ts + 14400000,
    );
    await addTransaction(
      id: 'credit_one_ms_outside',
      sourceId: 'src_f',
      direction: 'credit',
      ts: ts + 15000001,
    );

    expect(await repository.reconcileOwnedTransfers(), 2);
    final byId = {for (final row in await transactions()) row.id: row};
    expect(byId['debit_before']!.ownedTransferId, isNotNull);
    expect(byId['credit_at_plus_boundary']!.ownedTransferId, isNotNull);
    expect(byId['debit_after']!.ownedTransferId, isNotNull);
    expect(byId['credit_at_minus_boundary']!.ownedTransferId, isNotNull);
    expect(byId['debit_outside']!.ownedTransferId, isNull);
    expect(byId['credit_one_ms_outside']!.ownedTransferId, isNull);
  });

  test('abstains unless both sources have distinct known four-digit suffixes',
      () async {
    const ts = 1767225600000;
    final now = DateTime.utc(2026, 1, 1);
    const masks = {
      'same_a': 'XX1234',
      'same_b': 'xx-1234',
      'text_a': 'XX-text',
      'text_b': 'XX5678',
      'ok_a': 'XX1111',
      'ok_b': 'XX2222',
    };
    for (final entry in masks.entries) {
      await database.into(database.paymentSources).insert(
            PaymentSourcesCompanion.insert(
              id: entry.key,
              kind: 'bank',
              maskedIdentifier: entry.value,
              isOwned: const Value(true),
              isActive: const Value(true),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    var n = 0;
    for (final (debit, credit, amount) in [
      ('same_a', 'same_b', 100.0),
      ('text_a', 'text_b', 200.0),
      ('ok_a', 'ok_b', 300.0),
    ]) {
      await addTransaction(
        id: '${debit}_debit',
        sourceId: debit,
        direction: 'debit',
        ts: ts + n++,
        amount: amount,
      );
      await addTransaction(
        id: '${credit}_credit',
        sourceId: credit,
        direction: 'credit',
        ts: ts + n++,
        amount: amount,
      );
    }

    expect(await repository.reconcileOwnedTransfers(), 1);
    final linked = (await transactions())
        .where((row) => row.ownedTransferId != null)
        .map((row) => row.id)
        .toSet();
    expect(linked, {'ok_a_debit', 'ok_b_credit'});
  });

  test('requires matching currency code, symbol, and settled lifecycle',
      () async {
    const base = 1767225600000;
    await addSources([
      for (var i = 0; i < 12; i++) 'currency_source_$i',
    ]);
    final candidates = [
      ('inr_debit', 'inr_credit', 'INR', '₹', 'INR', '₹', 'settled'),
      ('usd_debit', 'usd_credit', 'USD', r'$', 'INR', r'$', 'settled'),
      ('symbol_debit', 'symbol_credit', 'INR', '₹', 'INR', r'Rs', 'settled'),
      ('unknown_debit', 'unknown_credit', null, null, null, null, 'settled'),
      ('pending_debit', 'pending_credit', 'INR', '₹', 'INR', '₹', 'pending'),
      (
        'unknown_symbol_debit',
        'unknown_symbol_credit',
        null,
        r'$',
        null,
        '₹',
        'settled'
      ),
    ];
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final offset = i * 2000000;
      await addTransaction(
        id: candidate.$1,
        sourceId: 'currency_source_${i * 2}',
        direction: 'debit',
        ts: base + offset,
        currencyCode: candidate.$3,
        currencySymbol: candidate.$4,
        lifecycleState: candidate.$7,
      );
      await addTransaction(
        id: candidate.$2,
        sourceId: 'currency_source_${i * 2 + 1}',
        direction: 'credit',
        ts: base + offset + 1000,
        currencyCode: candidate.$5,
        currencySymbol: candidate.$6,
        lifecycleState: candidate.$7,
      );
    }

    expect(await repository.reconcileOwnedTransfers(), 2);
    final byId = {for (final row in await transactions()) row.id: row};
    expect(byId['inr_debit']!.ownedTransferId, isNotNull);
    expect(byId['unknown_debit']!.ownedTransferId, isNotNull);
    for (final id in [
      'usd_debit',
      'symbol_debit',
      'pending_debit',
      'unknown_symbol_debit',
    ]) {
      expect(byId[id]!.ownedTransferId, isNull, reason: id);
    }
  });

  test('removes generated edge after a linked row becomes not a transaction',
      () async {
    const ts = 1767225600000;
    await addSources(['src_a', 'src_b']);
    await addTransaction(
      id: 'debit',
      sourceId: 'src_a',
      direction: 'debit',
      ts: ts,
    );
    await addTransaction(
      id: 'credit',
      sourceId: 'src_b',
      direction: 'credit',
      ts: ts + 1000,
    );
    await repository.reconcileOwnedTransfers();

    await (database.update(database.transactions)
          ..where((row) => row.id.equals('debit')))
        .write(const TransactionsCompanion(isNotTransaction: Value(true)));
    await repository.reconcileOwnedTransfers();

    expect(await links(), isEmpty);
    expect(
      (await transactions()).every((row) => row.ownedTransferId == null),
      isTrue,
    );
  });

  test('source deactivation reconciles stale edges and clears transfer flags',
      () async {
    const ts = 1767225600000;
    await addSources(['src_a', 'src_b']);
    await addTransaction(
      id: 'debit',
      sourceId: 'src_a',
      direction: 'debit',
      ts: ts,
    );
    await addTransaction(
      id: 'credit',
      sourceId: 'src_b',
      direction: 'credit',
      ts: ts + 1000,
    );
    await repository.reconcileOwnedTransfers();

    await repository.updateSource(
      sourceId: 'src_b',
      isActive: const Value(false),
      clock: () => DateTime.utc(2026, 1, 2),
    );

    expect(await links(), isEmpty);
    expect(
      (await transactions()).every((row) => row.ownedTransferId == null),
      isTrue,
    );
  });

  test(
      'payment-source edit removes old generated pair and creates its new pair',
      () async {
    const ts = 1767225600000;
    await addSources(['src_a', 'src_b', 'src_c']);
    await addTransaction(
      id: 'debit',
      sourceId: 'src_a',
      direction: 'debit',
      ts: ts,
    );
    await addTransaction(
      id: 'old_credit',
      sourceId: 'src_b',
      direction: 'credit',
      ts: ts + 1000,
    );
    expect(await repository.reconcileOwnedTransfers(), 1);

    await addTransaction(
      id: 'new_credit',
      sourceId: 'src_c',
      direction: 'credit',
      ts: ts + 2000,
    );
    await (database.update(database.transactions)
          ..where((row) => row.id.equals('old_credit')))
        .write(const TransactionsCompanion(paymentSourceId: Value('src_a')));
    await repository.reconcileOwnedTransfers();

    final generated = (await links())
        .where((link) => link.basis == 'indexed_owned_transfer')
        .toList();
    expect(generated, hasLength(1));
    expect(generated.single.fromTxnId, 'debit');
    expect(generated.single.toTxnId, 'new_credit');
    final byId = {for (final row in await transactions()) row.id: row};
    expect(byId['old_credit']!.ownedTransferId, isNull);
    expect(byId['debit']!.ownedTransferId, byId['new_credit']!.ownedTransferId);
  });

  test('amount and timestamp edits remove stale generated transfer edges',
      () async {
    const ts = 1767225600000;
    await addSources(['src_a', 'src_b']);
    await addTransaction(
      id: 'debit',
      sourceId: 'src_a',
      direction: 'debit',
      ts: ts,
    );
    await addTransaction(
      id: 'credit',
      sourceId: 'src_b',
      direction: 'credit',
      ts: ts + 1000,
    );
    expect(await repository.reconcileOwnedTransfers(), 1);

    await (database.update(database.transactions)
          ..where((row) => row.id.equals('debit')))
        .write(const TransactionsCompanion(amount: Value(600)));
    expect(await repository.reconcileOwnedTransfers(), 0);
    expect(await links(), isEmpty);
    expect(
      (await transactions()).every((row) => row.ownedTransferId == null),
      isTrue,
    );

    await (database.update(database.transactions)
          ..where((row) => row.id.equals('debit')))
        .write(
      const TransactionsCompanion(
        amount: Value(500),
        ts: Value(ts),
      ),
    );
    expect(await repository.reconcileOwnedTransfers(), 1);
    expect(await links(), hasLength(1));

    await (database.update(database.transactions)
          ..where((row) => row.id.equals('debit')))
        .write(
      const TransactionsCompanion(
        ts: Value(ts + 700000),
      ),
    );
    expect(await repository.reconcileOwnedTransfers(), 0);
    expect(await links(), isEmpty);
    expect(
      (await transactions()).every((row) => row.ownedTransferId == null),
      isTrue,
    );
  });

  test('length-prefixed transfer ids distinguish underscore collisions',
      () async {
    const ts = 1767225600000;
    await addSources(['source_1', 'source_2', 'source_3', 'source_4']);
    await addTransaction(
      id: 'a_b',
      sourceId: 'source_1',
      direction: 'debit',
      ts: ts,
    );
    await addTransaction(
      id: 'c',
      sourceId: 'source_2',
      direction: 'credit',
      ts: ts + 1000,
    );
    await addTransaction(
      id: 'a',
      sourceId: 'source_3',
      direction: 'debit',
      ts: ts + 7200000,
    );
    await addTransaction(
      id: 'b_c',
      sourceId: 'source_4',
      direction: 'credit',
      ts: ts + 7201000,
    );

    expect(await repository.reconcileOwnedTransfers(), 2);
    final byId = {for (final row in await transactions()) row.id: row};
    expect(
      byId['a_b']!.ownedTransferId,
      isNot(byId['a']!.ownedTransferId),
    );
  });

  test('keeps existing generated edge orientation and metadata for same pair',
      () async {
    const ts = 1767225600000;
    await addSources(['src_a', 'src_b']);
    await addTransaction(
      id: 'debit',
      sourceId: 'src_a',
      direction: 'debit',
      ts: ts,
    );
    await addTransaction(
      id: 'credit',
      sourceId: 'src_b',
      direction: 'credit',
      ts: ts + 1000,
    );
    const legacyEdge = TransactionLink(
      id: 'legacy_generated_edge',
      fromTxnId: 'credit',
      toTxnId: 'debit',
      linkType: 'transfer_leg',
      confidence: 0.73,
      basis: 'indexed_owned_transfer',
      createdBy: 'system',
      createdAt: 1234,
    );
    await database.into(database.transactionLinks).insert(legacyEdge);

    expect(await repository.reconcileOwnedTransfers(), 1);
    expect(await links(), [legacyEdge]);
  });

  test('ownership removal reconciles existing transfer flags and edge',
      () async {
    const ts = 1767225600000;
    await addSources(['src_a', 'src_b']);
    await addTransaction(
      id: 'debit',
      sourceId: 'src_a',
      direction: 'debit',
      ts: ts,
    );
    await addTransaction(
      id: 'credit',
      sourceId: 'src_b',
      direction: 'credit',
      ts: ts + 1000,
    );
    expect(await repository.reconcileOwnedTransfers(), 1);

    await repository.updateSource(
      sourceId: 'src_b',
      isOwned: const Value(false),
      clock: () => DateTime.utc(2026, 1, 2),
    );

    expect(await links(), isEmpty);
    expect(
      (await transactions()).every((row) => row.ownedTransferId == null),
      isTrue,
    );
  });

  test('preserves colliding user transfer link and remains idempotent',
      () async {
    const ts = 1767225600000;
    await addSources(['src_a', 'src_b']);
    await addTransaction(
      id: 'debit',
      sourceId: 'src_a',
      direction: 'debit',
      ts: ts,
    );
    await addTransaction(
      id: 'credit',
      sourceId: 'src_b',
      direction: 'credit',
      ts: ts + 1000,
    );
    const userCreatedAt = 17;
    await database.into(database.transactionLinks).insert(
          TransactionLinksCompanion.insert(
            id: 'link_debit_credit',
            fromTxnId: 'credit',
            toTxnId: 'debit',
            linkType: 'transfer_leg',
            basis: 'user_confirmed',
            createdBy: const Value('user'),
            createdAt: userCreatedAt,
          ),
        );

    var now = DateTime.utc(2026, 1, 2);
    expect(await repository.reconcileOwnedTransfers(clock: () => now), 1);
    final afterFirst = await links();
    final userLink = afterFirst.singleWhere((link) => link.createdBy == 'user');
    expect(userLink.fromTxnId, 'credit');
    expect(userLink.toTxnId, 'debit');
    expect(userLink.basis, 'user_confirmed');
    expect(userLink.createdAt, userCreatedAt);
    final generatedFirst =
        afterFirst.singleWhere((link) => link.createdBy == 'system');

    await database.into(database.transactionLinks).insert(
          TransactionLinksCompanion.insert(
            id: 'zz_duplicate_generated',
            fromTxnId: 'credit',
            toTxnId: 'debit',
            linkType: 'transfer_leg',
            basis: 'indexed_owned_transfer',
            createdBy: const Value('system'),
            confidence: const Value(0.4),
            createdAt: 1,
          ),
        );
    expect(await repository.reconcileOwnedTransfers(clock: () => now), 1);
    final afterDuplicateCleanup = await links();
    expect(afterDuplicateCleanup, hasLength(2));
    expect(
      afterDuplicateCleanup.any((link) => link.id == 'zz_duplicate_generated'),
      isFalse,
    );
    final retainedBeforeIdempotency =
        afterDuplicateCleanup.singleWhere((link) => link.createdBy == 'system');
    expect(retainedBeforeIdempotency, generatedFirst);

    for (final trigger in [
      'CREATE TABLE transfer_write_audit (kind TEXT NOT NULL)',
      '''CREATE TRIGGER audit_transfer_txn_update AFTER UPDATE ON transactions BEGIN
        INSERT INTO transfer_write_audit VALUES ('transaction_update');
      END''',
      '''CREATE TRIGGER audit_transfer_link_insert AFTER INSERT ON transaction_links BEGIN
        INSERT INTO transfer_write_audit VALUES ('link_insert');
      END''',
      '''CREATE TRIGGER audit_transfer_link_update AFTER UPDATE ON transaction_links BEGIN
        INSERT INTO transfer_write_audit VALUES ('link_update');
      END''',
      '''CREATE TRIGGER audit_transfer_link_delete AFTER DELETE ON transaction_links BEGIN
        INSERT INTO transfer_write_audit VALUES ('link_delete');
      END''',
    ]) {
      await database.customStatement(trigger);
    }
    final triggerCount = await database.customSelect('''
SELECT COUNT(*) AS count FROM sqlite_master
WHERE type = 'trigger' AND name LIKE 'audit_transfer_%'
''').getSingle();
    expect(triggerCount.read<int>('count'), 4);
    await database.customStatement('DELETE FROM transfer_write_audit');
    now = now.add(const Duration(days: 1));

    expect(await repository.reconcileOwnedTransfers(clock: () => now), 1);
    final audit = await database
        .customSelect('SELECT COUNT(*) AS count FROM transfer_write_audit')
        .getSingle();
    expect(audit.read<int>('count'), 0);
    final afterSecond = await links();
    final userAfterSecond =
        afterSecond.singleWhere((link) => link.createdBy == 'user');
    final generatedSecond =
        afterSecond.singleWhere((link) => link.createdBy == 'system');
    expect(generatedSecond.id, generatedFirst.id);
    expect(generatedSecond.fromTxnId, generatedFirst.fromTxnId);
    expect(generatedSecond.toTxnId, generatedFirst.toTxnId);
    expect(generatedSecond.createdAt, generatedFirst.createdAt);
    expect(userAfterSecond, userLink);
  });

  test('keeps transfer legs excluded from aggregate totals exactly once',
      () async {
    const ts = 1767225600000;
    await addSources(['src_a', 'src_b', 'src_c']);
    await addTransaction(
      id: 'transfer_debit',
      sourceId: 'src_a',
      direction: 'debit',
      ts: ts,
      amount: 1200,
    );
    await addTransaction(
      id: 'transfer_credit',
      sourceId: 'src_b',
      direction: 'credit',
      ts: ts + 1000,
      amount: 1200,
    );
    await addTransaction(
      id: 'purchase',
      sourceId: 'src_c',
      direction: 'debit',
      ts: ts + 2000,
      amount: 700,
    );

    await repository.reconcileOwnedTransfers();
    final total = await database.customSelect('''
SELECT COALESCE(SUM(t.amount), 0) AS total
FROM transactions t
LEFT JOIN categories c ON c.id = t.category_id
WHERE ${FinancialEligibility.spendingDebitSql}
''').getSingle();
    expect(total.read<double>('total'), 700);
  });

  test('dashboard aggregates exclude both transfer legs and keep the purchase',
      () async {
    final base = DateTime.utc(2026, 7, 10);
    await addSources(['src_a', 'src_b', 'src_c']);
    await addTransaction(
      id: 'transfer_debit',
      sourceId: 'src_a',
      direction: 'debit',
      ts: base.millisecondsSinceEpoch,
      amount: 1200,
      currencyCode: 'INR',
      currencySymbol: '₹',
    );
    await addTransaction(
      id: 'transfer_credit',
      sourceId: 'src_b',
      direction: 'credit',
      ts: base.millisecondsSinceEpoch + 1000,
      amount: 1200,
      currencyCode: 'INR',
      currencySymbol: '₹',
    );
    await addTransaction(
      id: 'purchase',
      sourceId: 'src_c',
      direction: 'debit',
      ts: base.millisecondsSinceEpoch + 2000,
      amount: 700,
      currencyCode: 'INR',
      currencySymbol: '₹',
    );
    await repository.reconcileOwnedTransfers();

    final snapshot = await DashboardRepository(database).load(
      DashboardQueryWindow(
        start: DateTime.utc(2026, 7, 1),
        end: DateTime.utc(2026, 8, 1),
        previousStart: DateTime.utc(2026, 6, 1),
        previousEnd: DateTime.utc(2026, 7, 1),
        trendStart: DateTime.utc(2026, 2, 1),
        trendEnd: DateTime.utc(2026, 8, 1),
      ),
    );
    expect(snapshot.debitTotal, 700);
    expect(snapshot.creditTotal, 0);
  });

  test('failed generated edge insert rolls back flags and edge cleanup',
      () async {
    const ts = 1767225600000;
    await addSources(['src_a', 'src_b', 'src_c']);
    await addTransaction(
      id: 'debit',
      sourceId: 'src_a',
      direction: 'debit',
      ts: ts,
    );
    await addTransaction(
      id: 'old_credit',
      sourceId: 'src_b',
      direction: 'credit',
      ts: ts + 1000,
    );
    await repository.reconcileOwnedTransfers();
    final oldLink = (await links()).single;
    final oldRows = {for (final row in await transactions()) row.id: row};

    await (database.update(database.transactions)
          ..where((row) => row.id.equals('old_credit')))
        .write(const TransactionsCompanion(amount: Value(700)));
    await addTransaction(
      id: 'new_credit',
      sourceId: 'src_c',
      direction: 'credit',
      ts: ts + 2000,
    );
    await database.customStatement('''
CREATE TRIGGER reject_transfer_edge BEFORE INSERT ON transaction_links
WHEN NEW.created_by = 'system' AND NEW.basis = 'indexed_owned_transfer'
BEGIN SELECT RAISE(ABORT, 'synthetic transfer edge failure'); END
''');

    await expectLater(repository.reconcileOwnedTransfers(), throwsA(anything));
    expect(await links(), [oldLink]);
    final after = {for (final row in await transactions()) row.id: row};
    expect(after['debit']!.ownedTransferId, oldRows['debit']!.ownedTransferId);
    expect(
      after['old_credit']!.ownedTransferId,
      oldRows['old_credit']!.ownedTransferId,
    );
  });

  test('deletes large stale generated edge sets in bounded SQLite batches',
      () async {
    const ts = 1767225600000;
    const staleLinkCount = 1205;
    await addSources(['src_a', 'src_b']);
    await addTransaction(
      id: 'debit',
      sourceId: 'src_a',
      direction: 'debit',
      ts: ts,
    );
    await addTransaction(
      id: 'credit',
      sourceId: 'src_b',
      direction: 'credit',
      ts: ts + 1000,
    );
    await (database.update(database.transactions)
          ..where((row) => row.id.equals('debit')))
        .write(const TransactionsCompanion(isNotTransaction: Value(true)));
    await database.batch((batch) {
      batch.insertAll(
        database.transactionLinks,
        [
          for (var i = 0; i < staleLinkCount; i++)
            TransactionLinksCompanion.insert(
              id: 'stale_generated_$i',
              fromTxnId: 'debit',
              toTxnId: 'credit',
              linkType: 'transfer_leg',
              basis: 'indexed_owned_transfer',
              createdBy: const Value('system'),
              createdAt: i,
            ),
        ],
      );
    });

    expect(await repository.reconcileOwnedTransfers(), 0);
    expect(await links(), isEmpty);
  });

  test(
      'ambiguous dense history stays unresolved without quadratic materialization',
      () async {
    const base = 1767225600000;
    const perDirection = 80;
    await addSources([
      for (var i = 0; i < perDirection * 2; i++) 'dense_source_$i',
      'history_debit_source',
      'history_credit_source',
    ]);
    final history = [
      for (var i = 0; i < 10000; i++)
        TransactionsCompanion.insert(
          id: 'history_$i',
          ts: base - 30000000 - i * 120000,
          amount: 9000.0 + i,
          direction: i.isEven ? 'debit' : 'credit',
          channel: 'upi',
          paymentSourceId: Value(
            i.isEven ? 'history_debit_source' : 'history_credit_source',
          ),
          parseSource: 'template',
          confidenceJson: '{}',
          status: 'confirmed',
          createdAt: DateTime.fromMillisecondsSinceEpoch(base, isUtc: true),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(base, isUtc: true),
        ),
    ];
    await database.batch((batch) {
      batch.insertAll(database.transactions, history);
    });
    for (var i = 0; i < perDirection; i++) {
      await addTransaction(
        id: 'dense_debit_$i',
        sourceId: 'dense_source_$i',
        direction: 'debit',
        ts: base + i,
        amount: 9999,
      );
      await addTransaction(
        id: 'dense_credit_$i',
        sourceId: 'dense_source_${i + perDirection}',
        direction: 'credit',
        ts: base + i,
        amount: 9999,
      );
    }

    final watch = Stopwatch()..start();
    final pairs = await repository.reconcileOwnedTransfers();
    watch.stop();
    // Informational timing makes local performance reproducible without a
    // brittle machine-dependent duration threshold.
    // ignore: avoid_print
    print(
      'T-165b benchmark: ${10000 + perDirection * 2} rows, '
      '$perDirection x $perDirection dense candidates, '
      '${watch.elapsedMilliseconds} ms',
    );
    expect(pairs, 0);
    expect(
      (await transactions()).every((row) => row.ownedTransferId == null),
      isTrue,
    );
  });
}

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/payee_evidence_repository.dart';
import 'package:paisatrack/data/repositories/payee_label_repository.dart';

void main() {
  late AppDatabase database;
  late PayeeLabelRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = PayeeLabelRepository(database);
  });

  tearDown(() => database.close());

  Future<void> insertTransaction({
    required String id,
    String? merchantRaw,
    String? counterpartyVpa,
    String? merchantId,
    bool isDeleted = false,
    String? duplicateOfTxnId,
  }) async {
    final now = DateTime.utc(2026, 7, 16);
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            ts: now.millisecondsSinceEpoch,
            amount: 250,
            direction: 'debit',
            channel: 'upi',
            merchantRaw: Value(merchantRaw),
            counterpartyVpa: Value(counterpartyVpa),
            merchantId: Value(merchantId),
            isDeleted: Value(isDeleted),
            duplicateOfTxnId: Value(duplicateOfTxnId),
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'confirmed',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await PayeeEvidenceRepository(database).replaceForTransaction(
      transactionId: id,
      merchantRaw: merchantRaw,
      counterpartyVpa: counterpartyVpa,
    );
  }

  test('maps multiple aliases and preserves original transaction evidence',
      () async {
    await insertTransaction(
      id: 'txn_1',
      merchantRaw: 'AMZN Mktplace',
      counterpartyVpa: 'amazon@apl',
    );
    await insertTransaction(id: 'txn_2', merchantRaw: 'Amazon Pay India');

    final preview = await repository.preview(
      aliases: const ['AMZN Mktplace', 'amazon@apl', 'Amazon Pay India'],
    );
    expect(preview.affectedTransactionCount, 2);
    expect(preview.hasConflicts, isFalse);

    final affected = await repository.saveLabel(
      label: 'Amazon',
      aliases: const ['AMZN Mktplace', 'amazon@apl', 'Amazon Pay India'],
      clock: () => DateTime.utc(2026, 7, 16, 1),
    );
    expect(affected, 2);

    final merchant = await database.select(database.merchants).getSingle();
    expect(merchant.userLabel, 'Amazon');
    final aliases = await database.select(database.merchantAliases).get();
    expect(aliases, hasLength(3));
    expect(aliases.every((row) => row.source == 'user'), isTrue);

    final transactions = await database.select(database.transactions).get();
    expect(
      transactions.map((row) => row.merchantId),
      everyElement(merchant.id),
    );
    expect(
      transactions.map((row) => row.merchantRaw),
      containsAll(['AMZN Mktplace', 'Amazon Pay India']),
    );
    expect(transactions.first.counterpartyVpa, 'amazon@apl');
  });

  test('refuses aliases that would merge two existing payees', () async {
    final now = DateTime.utc(2026, 7, 16);
    for (final entry
        in const {'merchant_a': 'Alice', 'merchant_b': 'Bob'}.entries) {
      await database.into(database.merchants).insert(
            MerchantsCompanion.insert(
              id: entry.key,
              canonicalName: entry.value,
              firstSeen: now,
              lastSeen: now,
            ),
          );
    }
    await database.into(database.merchantAliases).insert(
          MerchantAliasesCompanion.insert(
            alias: 'ALICEOKHDFC',
            merchantId: 'merchant_a',
            source: 'new',
            confidence: 1,
          ),
        );
    await database.into(database.merchantAliases).insert(
          MerchantAliasesCompanion.insert(
            alias: 'BOBOKICICI',
            merchantId: 'merchant_b',
            source: 'new',
            confidence: 1,
          ),
        );

    final preview = await repository.preview(
      aliases: const ['alice@okhdfc', 'bob@okicici'],
    );
    expect(preview.hasConflicts, isTrue);
    expect(
      () => repository.saveLabel(
        label: 'Family',
        aliases: const ['alice@okhdfc', 'bob@okicici'],
      ),
      throwsA(isA<PayeeAliasConflict>()),
    );
  });

  test(
      'loads SQL-grouped identities with bounded aliases and eligibility rules',
      () async {
    final now = DateTime.utc(2026, 7, 16);
    await database.into(database.merchants).insert(
          MerchantsCompanion.insert(
            id: 'merchant_alpha',
            canonicalName: 'Alpha',
            firstSeen: now,
            lastSeen: now,
          ),
        );
    await database.into(database.merchants).insert(
          MerchantsCompanion.insert(
            id: 'merchant_labeled',
            canonicalName: 'Beta',
            userLabel: const Value('Groceries'),
            firstSeen: now,
            lastSeen: now,
          ),
        );
    await insertTransaction(
      id: 'merchant_txn',
      merchantId: 'merchant_alpha',
      merchantRaw: 'Alpha Store',
    );
    await insertTransaction(
      id: 'labeled_txn',
      merchantId: 'merchant_labeled',
      merchantRaw: 'Beta Store',
    );
    await insertTransaction(id: 'unresolved_1', merchantRaw: 'Foo-Bar');
    await insertTransaction(id: 'unresolved_2', merchantRaw: 'FOOBAR');
    await insertTransaction(
      id: 'unresolved_3',
      counterpartyVpa: 'foo@upi',
      merchantRaw: 'Foo-Bar',
    );
    await insertTransaction(
      id: 'deleted',
      merchantRaw: 'Should Not Show',
      isDeleted: true,
    );
    await insertTransaction(
      id: 'duplicate',
      merchantRaw: 'Should Not Show',
      duplicateOfTxnId: 'merchant_txn',
    );

    final page = await repository.loadPage(
      const PayeeIdentityQuery(limit: 10),
    );
    expect(
      page.items.map((item) => item.key),
      containsAll([
        'merchant:merchant_alpha',
        'merchant:merchant_labeled',
        'alias:FOOBAR',
      ]),
    );
    expect(page.items, hasLength(3));
    final unresolved =
        page.items.singleWhere((item) => item.key == 'alias:FOOBAR');
    expect(unresolved.transactionCount, 3);
    expect(unresolved.aliases, containsAll(['Foo-Bar', 'FOOBAR', 'foo@upi']));
    final alpha = page.items.singleWhere(
      (item) => item.key == 'merchant:merchant_alpha',
    );
    expect(alpha.transactionCount, 1);
    expect(alpha.aliases, ['Alpha Store']);
  });

  test('searches aliases and filters unlabeled identities in SQL', () async {
    final now = DateTime.utc(2026, 7, 16);
    await database.into(database.merchants).insert(
          MerchantsCompanion.insert(
            id: 'merchant_labeled',
            canonicalName: 'Labeled',
            userLabel: const Value('Known Payee'),
            firstSeen: now,
            lastSeen: now,
          ),
        );
    await insertTransaction(
      id: 'labeled_txn',
      merchantId: 'merchant_labeled',
      merchantRaw: 'Hidden Alias',
    );
    await insertTransaction(id: 'unlabeled_txn', merchantRaw: 'Visible Alias');

    final aliasSearch = await repository.loadPage(
      const PayeeIdentityQuery(search: 'hidden alias'),
    );
    expect(aliasSearch.items.single.displayName, 'Known Payee');
    final unlabeled = await repository.loadPage(
      const PayeeIdentityQuery(unlabeledOnly: true),
    );
    expect(unlabeled.items.map((item) => item.displayName), ['Visible Alias']);
  });

  test('uses a stable keyset cursor without repeating page items', () async {
    final now = DateTime.utc(2026, 7, 16);
    for (final name in const ['Alpha', 'Beta', 'Gamma']) {
      await database.into(database.merchants).insert(
            MerchantsCompanion.insert(
              id: 'merchant_$name',
              canonicalName: name,
              firstSeen: now,
              lastSeen: now,
            ),
          );
      await insertTransaction(id: 'txn_$name', merchantId: 'merchant_$name');
    }

    final first = await repository.loadPage(
      const PayeeIdentityQuery(limit: 2),
    );
    expect(first.items.map((item) => item.displayName), ['Alpha', 'Beta']);
    expect(first.hasMore, isTrue);
    final second = await repository.loadPage(
      PayeeIdentityQuery(limit: 2, after: first.nextCursor),
    );
    expect(second.items.map((item) => item.displayName), ['Gamma']);
    expect(second.hasMore, isFalse);
  });

  test('keeps page size bounded at realistic transaction volume', () async {
    final now = DateTime.utc(2026, 7, 16);
    final rows = [
      for (var i = 0; i < 2000; i++)
        TransactionsCompanion.insert(
          id: 'volume_$i',
          ts: now.millisecondsSinceEpoch + i,
          amount: 100.0 + i,
          direction: 'debit',
          channel: 'upi',
          merchantRaw: Value('Payee $i'),
          parseSource: 'test',
          confidenceJson: '{}',
          status: 'confirmed',
          createdAt: now,
          updatedAt: now,
        ),
    ];
    await database.batch((batch) {
      batch.insertAll(database.transactions, rows);
    });
    await PayeeEvidenceRepository(database).rebuild();

    final page = await repository.loadPage(
      const PayeeIdentityQuery(limit: 25),
    );
    expect(page.items, hasLength(25));
    expect(page.hasMore, isTrue);
    final searched = await repository.loadPage(
      const PayeeIdentityQuery(search: 'Payee 1999', limit: 25),
    );
    expect(searched.items.single.aliases, ['Payee 1999']);
  });
}

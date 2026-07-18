import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
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
  }) {
    final now = DateTime.utc(2026, 7, 16);
    return database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            ts: now.millisecondsSinceEpoch,
            amount: 250,
            direction: 'debit',
            channel: 'upi',
            merchantRaw: Value(merchantRaw),
            counterpartyVpa: Value(counterpartyVpa),
            merchantId: Value(merchantId),
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'confirmed',
            createdAt: now,
            updatedAt: now,
          ),
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
}

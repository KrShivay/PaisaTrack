import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/card_source_audit_repository.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.customSelect('SELECT 1').get();
  });

  tearDown(() => database.close());

  test('SQL aggregates lifecycle and currency groups and masks identifiers',
      () async {
    final now = DateTime.utc(2026, 10, 1, 10);
    await _insertSource(
      database,
      id: 'card-source',
      kind: 'card',
      mask: '4111111111111234',
      now: now,
    );
    await _insertTransaction(
      database,
      id: 'card-settled',
      accountHint: '4111111111111234',
      channel: 'card',
      paymentSourceId: 'card-source',
      timestamp: now,
      currencyCode: 'USD',
      currencySymbol: r'$',
    );
    await _insertTransaction(
      database,
      id: 'card-settled-same-bucket',
      accountHint: '4111111111111234',
      channel: 'card',
      paymentSourceId: 'card-source',
      timestamp: now.add(const Duration(minutes: 1)),
      currencyCode: 'USD',
      currencySymbol: r'$',
    );
    await _insertTransaction(
      database,
      id: 'card-pending',
      accountHint: '4111111111111234',
      channel: 'card',
      paymentSourceId: 'card-source',
      timestamp: now.add(const Duration(minutes: 2)),
      lifecycleState: 'pending',
    );
    await _insertTransaction(
      database,
      id: 'card-blank-currency',
      accountHint: '4111111111111234',
      channel: 'card',
      paymentSourceId: 'card-source',
      timestamp: now.add(const Duration(minutes: 3)),
      currencyCode: '',
      currencySymbol: '',
    );
    await _insertTransaction(
      database,
      id: 'card-whitespace-currency',
      accountHint: '4111111111111234',
      channel: 'card',
      paymentSourceId: 'card-source',
      timestamp: now.add(const Duration(minutes: 4)),
      currencyCode: '   ',
      currencySymbol: '   ',
    );
    await _insertTransaction(
      database,
      id: 'wallet-txn',
      accountHint: 'xx5678',
      channel: 'wallet',
      timestamp: now,
    );

    final report = await CardSourceAuditRepository(database).load();
    final card = report.sources.singleWhere((source) => source.kind == 'card');

    expect(card.maskedIdentifier, '••••1234');
    expect(card.maskedIdentifier, isNot(contains('411111')));
    expect(card.nickname, 'Not recorded');
    expect(card.institution, 'Not recorded');
    expect(card.rowCount, 5);
    expect(
      card.buckets
          .map((bucket) => '${bucket.lifecycleState}:${bucket.rowCount}'),
      containsAll(['settled:2', 'pending:1']),
    );
    expect(
      card.buckets
          .singleWhere((bucket) => bucket.currencyCode == 'USD')
          .rowCount,
      2,
    );
    expect(
      card.buckets.map((bucket) => bucket.currencyLabel),
      containsAll([
        r'USD · $',
        'Currency unavailable',
        'Blank code · blank symbol',
        'Whitespace-only code · whitespace-only symbol',
      ]),
    );
    expect(report.candidates, hasLength(5));
    expect(
      report.candidates.every(
        (candidate) => !candidate.maskedIdentifier.contains('411111'),
      ),
      isTrue,
    );
    expect(
      report.candidates
          .singleWhere((row) => row.id == 'card-pending')
          .lifecycleState,
      'pending',
    );
    expect(report.candidatesTruncated, isFalse);
  });

  test('candidate paging is bounded and deterministic for equal timestamps',
      () async {
    final now = DateTime.utc(2026, 10, 1, 10);
    for (final id in ['a', 'b', 'c', 'd', 'e']) {
      await _insertTransaction(
        database,
        id: id,
        channel: 'card',
        timestamp: now,
      );
    }
    final repository = CardSourceAuditRepository(database, pageSize: 2);

    final first = await repository.load();
    final second = await repository.load(cursor: first.nextCursor);
    final third = await repository.load(cursor: second.nextCursor);

    expect(first.candidates.map((row) => row.id), ['e', 'd']);
    expect(second.candidates.map((row) => row.id), ['c', 'b']);
    expect(third.candidates.map((row) => row.id), ['a']);
    expect(first.candidatesTruncated, isTrue);
    expect(second.candidatesTruncated, isTrue);
    expect(third.candidatesTruncated, isFalse);
    expect(
      [
        ...first.candidates,
        ...second.candidates,
        ...third.candidates,
      ].map((row) => row.id).toSet(),
      hasLength(5),
    );
  });

  test('bounds requested page sizes and bucket groups while keeping totals',
      () async {
    final now = DateTime.utc(2026, 10, 1, 10);
    await _insertSource(
      database,
      id: 'many-buckets',
      kind: 'card',
      mask: 'XX4444',
      now: now,
    );
    for (var index = 0; index < 25; index++) {
      await _insertTransaction(
        database,
        id: 'bucket-$index',
        accountHint: 'XX4444',
        channel: 'card',
        paymentSourceId: 'many-buckets',
        timestamp: now.add(Duration(minutes: index)),
        lifecycleState: 'state-$index',
        currencyCode: 'CODE-$index',
      );
    }

    final source =
        (await CardSourceAuditRepository(database).load()).sources.single;
    expect(source.rowCount, 25);
    expect(source.buckets, hasLength(20));
    expect(source.totalBucketCount, 25);
    expect(source.bucketsTruncated, isTrue);
    expect(
      () => CardSourceAuditRepository(database, pageSize: 101),
      throwsArgumentError,
    );
  });

  test('empty sources have no fabricated currency/lifecycle bucket', () async {
    final now = DateTime.utc(2026, 10, 1, 10);
    await _insertSource(
      database,
      id: 'empty-source',
      kind: 'unknown',
      mask: 'not-an-identifier',
      now: now,
    );

    final source =
        (await CardSourceAuditRepository(database).load()).sources.single;
    expect(source.rowCount, 0);
    expect(source.buckets, isEmpty);
    expect(source.totalBucketCount, 0);
    expect(source.bucketsTruncated, isFalse);
    expect(source.maskedIdentifier, 'Not available');
  });

  test('reports only collisions backed by stored source provenance', () async {
    final now = DateTime.utc(2026, 10, 1, 10);
    await _insertSource(
      database,
      id: 'source-a',
      kind: 'card',
      mask: 'XX 1234',
      institution: 'Stored Bank A',
      now: now,
    );
    await _insertSource(
      database,
      id: 'source-b',
      kind: 'card',
      mask: 'XX-1234',
      institution: 'Stored Bank B',
      now: now,
    );
    await _insertTransaction(
      database,
      id: 'mapped-a',
      channel: 'card',
      accountHint: 'XX 1234',
      paymentSourceId: 'source-a',
      timestamp: now,
    );
    await _insertTransaction(
      database,
      id: 'mapped-b',
      channel: 'card',
      accountHint: 'xx1234',
      paymentSourceId: 'source-b',
      timestamp: now.add(const Duration(minutes: 1)),
    );
    await _insertTransaction(
      database,
      id: 'single-stored-source',
      channel: 'upi',
      accountHint: 'xx9999',
      timestamp: now,
    );

    final report = await CardSourceAuditRepository(database).load();

    expect(report.conflicts, hasLength(1));
    expect(report.conflicts.single.channel, 'card');
    expect(report.conflicts.single.maskedIdentifier, '••••1234');
    expect(report.conflicts.single.sourceIdCount, 2);
    expect(report.conflicts.single.institutionLabelCount, 2);
    expect(report.conflicts.single.hasUnlinkedRows, isFalse);
    expect(
      maskStoredHint('an unstructured private identifier'),
      'Not available',
    );
    expect(maskStoredHint('123'), 'Not available');
    expect(maskStoredHint('1234567890123456'), '••••3456');
  });

  test('retains candidate rows despite exclusion and lifecycle flags',
      () async {
    final now = DateTime.utc(2026, 10, 1, 10);
    await _insertSource(
      database,
      id: 'source',
      kind: 'card',
      mask: 'XX4444',
      now: now,
    );
    await _insertTransaction(
      database,
      id: 'deleted',
      channel: 'card',
      paymentSourceId: 'source',
      timestamp: now,
      isDeleted: true,
    );
    await _insertTransaction(
      database,
      id: 'not-a-transaction',
      channel: 'card',
      paymentSourceId: 'source',
      timestamp: now.add(const Duration(minutes: 1)),
      isNotTransaction: true,
      lifecycleState: 'failed',
    );

    final report = await CardSourceAuditRepository(database).load();
    final deleted = report.candidates.singleWhere((row) => row.id == 'deleted');
    final falsePositive =
        report.candidates.singleWhere((row) => row.id == 'not-a-transaction');

    expect(deleted.isDeleted, isTrue);
    expect(falsePositive.isNotTransaction, isTrue);
    expect(falsePositive.lifecycleState, 'failed');
    expect(report.sources.single.rowCount, 2);
  });
}

Future<void> _insertSource(
  AppDatabase database, {
  required String id,
  required String kind,
  required String mask,
  String? institution,
  required DateTime now,
}) async {
  await database.into(database.paymentSources).insert(
        PaymentSourcesCompanion.insert(
          id: id,
          kind: kind,
          maskedIdentifier: mask,
          institution: Value(institution),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _insertTransaction(
  AppDatabase database, {
  required String id,
  required String channel,
  required DateTime timestamp,
  String? accountHint,
  String? paymentSourceId,
  String direction = 'debit',
  double amount = 500,
  String? currencyCode,
  String? currencySymbol,
  String lifecycleState = 'settled',
  bool isDeleted = false,
  bool isNotTransaction = false,
}) async {
  await database.into(database.transactions).insert(
        TransactionsCompanion.insert(
          id: id,
          ts: timestamp.millisecondsSinceEpoch,
          amount: amount,
          direction: direction,
          channel: channel,
          accountHint: Value(accountHint),
          paymentSourceId: Value(paymentSourceId),
          currencyCode: Value(currencyCode),
          currencySymbol: Value(currencySymbol),
          lifecycleState: Value(lifecycleState),
          isDeleted: Value(isDeleted),
          isNotTransaction: Value(isNotTransaction),
          parseSource: 'template',
          confidenceJson: '{}',
          status: 'confirmed',
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
}

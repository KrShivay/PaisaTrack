import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/constants.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/repositories/trends_inbox_repository.dart';

void main() {
  late AppDatabase database;
  late TrendsInboxRepository repository;
  var databaseClosed = false;

  setUp(() {
    databaseClosed = false;
    database = AppDatabase(NativeDatabase.memory());
    repository = TrendsInboxRepository(database);
  });

  tearDown(() async {
    if (!databaseClosed) await database.close();
  });

  test('creates from a valid claim and updates repeated crossing in place',
      () async {
    final first = _claim(period: '2026-10', currentTotal: 120);
    final repeated = _claim(period: '2026-10', currentTotal: 180);

    final created = await repository.reconcile(
      period: '2026-10',
      freshClaims: [first],
    );
    final updated = await repository.reconcile(
      period: '2026-10',
      freshClaims: [repeated],
    );

    expect(created, hasLength(1));
    expect(created.single.state, TrendsInboxState.newItem);
    expect(updated, hasLength(1));
    expect(updated.single.key, created.single.key);
    expect(updated.single.claim.metrics['current_total'], 180);
    expect(updated.single.state, TrendsInboxState.newItem);
    final metadata = await (database.select(database.modelMeta)
          ..where((row) => row.key.equals(trendsInboxModelMetaKey)))
        .getSingle();
    expect(metadata.value, contains('"state":"new"'));
    expect(metadata.value, isNot(contains('untrusted_text')));
    expect(metadata.value, isNot(contains('raw SMS must never')));
  });

  test('calendar period change creates a separate item', () async {
    final october = await repository.reconcile(
      period: '2026-10',
      freshClaims: [_claim(period: '2026-10')],
    );
    final november = await repository.reconcile(
      period: '2026-11',
      freshClaims: [_claim(period: '2026-11')],
    );

    expect(november, hasLength(1));
    expect(november.single.key, isNot(october.single.key));
    expect(await repository.readAll(), hasLength(2));
  });

  test('Clear all affects visible items in that period only', () async {
    await repository.reconcile(
      period: '2026-10',
      freshClaims: [_claim(period: '2026-10')],
    );
    await repository.reconcile(
      period: '2026-11',
      freshClaims: [_claim(period: '2026-11')],
    );

    await repository.clearAll(period: '2026-10');

    expect(
      (await repository.readPeriod('2026-10')).single.state,
      TrendsInboxState.cleared,
    );
    expect(
      (await repository.readPeriod('2026-11')).single.state,
      TrendsInboxState.newItem,
    );
  });

  test('restore returns a cleared item to seen and un-dismisses it', () async {
    final insight = _claim(period: '2026-10');
    await database.into(database.insights).insert(
          InsightsCompanion.insert(
            id: insight.id,
            period: insight.period,
            kind: insight.kind,
            payloadJson: insight.payloadJson,
          ),
        );
    final items = await repository.reconcile(
      period: '2026-10',
      freshClaims: [insight],
    );
    await repository.clear(items.single.key);
    expect(
      (await repository.readAll()).single.state,
      TrendsInboxState.cleared,
    );

    await repository.restore(items.single.key);

    expect((await repository.readAll()).single.state, TrendsInboxState.seen);
    final row = await (database.select(database.insights)
          ..where((r) => r.id.equals(insight.id)))
        .getSingle();
    expect(row.dismissed, isFalse);

    await repository.moveToLater(items.single.key);
    await repository.restore(items.single.key);
    expect((await repository.readAll()).single.state, TrendsInboxState.moved);
    await repository.restore('missing');
  });

  test('legacy stored JSON with cleared items still parses via readAll',
      () async {
    final insight = _claim(period: '2026-10');
    final legacy = jsonEncode({
      'v': 1,
      'items': {
        'legacy-key': {
          'state': 'cleared',
          'current': false,
          'insight': {
            'id': insight.id,
            'period': insight.period,
            'kind': insight.kind,
            'payload': insight.payloadJson,
            'dismissed': true,
          },
        },
      },
    });
    await database.into(database.modelMeta).insert(
          ModelMetaCompanion.insert(
            key: trendsInboxModelMetaKey,
            value: legacy,
          ),
        );

    final items = await repository.readAll();

    expect(items.single.key, 'legacy-key');
    expect(items.single.state, TrendsInboxState.cleared);
    expect(items.single.isCurrent, isFalse);
  });

  test('claim dropping on recompute retains last snapshot as not current',
      () async {
    await repository.reconcile(
      period: '2026-10',
      freshClaims: [_claim(period: '2026-10')],
    );

    final items = await repository.reconcile(
      period: '2026-10',
      freshClaims: const [],
    );

    expect(items, hasLength(1));
    expect(items.single.isCurrent, isFalse);
    expect(items.single.claim.metrics['current_total'], 120);
  });

  test('clear all persists across database re-open and Undo restores states',
      () async {
    final directory = await Directory.systemTemp.createTemp('trends-inbox');
    final file = File('${directory.path}/test.sqlite');
    addTearDown(() async => directory.delete(recursive: true));
    await database.close();
    databaseClosed = true;
    var fileDatabase = AppDatabase(NativeDatabase(file));
    var fileRepository = TrendsInboxRepository(fileDatabase);
    await fileRepository.reconcile(
      period: '2026-10',
      freshClaims: [
        _claim(period: '2026-10'),
        _claim(kind: 'fees_total', period: '2026-10'),
      ],
    );
    var items = await fileRepository.readPeriod('2026-10');
    await fileRepository.markSeen(items.first.key);
    final beforeClear = await fileRepository.readPeriod('2026-10');
    final undo = await fileRepository.clearAll(period: '2026-10');
    await fileDatabase.close();

    final reopenedDatabase = AppDatabase(NativeDatabase(file));
    final restartedContainer = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => reopenedDatabase),
      ],
    );
    addTearDown(restartedContainer.dispose);
    fileDatabase = await restartedContainer.read(appDatabaseProvider.future);
    fileRepository = TrendsInboxRepository(fileDatabase);
    items = await fileRepository.readPeriod('2026-10');
    expect(
      items.every((item) => item.state == TrendsInboxState.cleared),
      isTrue,
    );

    await fileRepository.undoClearAll(undo);
    items = await fileRepository.readPeriod('2026-10');
    expect(
      {for (final item in items) item.key: item.state},
      {for (final item in beforeClear) item.key: item.state},
    );
    await fileDatabase.close();
  });

  test('move and return preserve the item key', () async {
    final items = await repository.reconcile(
      period: '2026-10',
      freshClaims: [_claim(period: '2026-10')],
    );
    final key = items.single.key;

    await repository.moveToLater(key);
    expect(
      (await repository.readPeriod('2026-10')).single.state,
      TrendsInboxState.moved,
    );
    await repository.returnToSeen(key);
    expect(
      (await repository.readPeriod('2026-10')).single.state,
      TrendsInboxState.seen,
    );
  });

  test('overlapping clear all and reconcile cannot restore a cleared item',
      () async {
    final claim = _claim(period: '2026-10');
    final items = await repository.reconcile(
      period: '2026-10',
      freshClaims: [claim],
    );

    await Future.wait([
      repository.clearAll(period: '2026-10'),
      repository.reconcile(period: '2026-10', freshClaims: [claim]),
    ]);

    expect(
      (await repository.readPeriod('2026-10'))
          .singleWhere((item) => item.key == items.single.key)
          .state,
      TrendsInboxState.cleared,
    );
  });

  test('overlapping move and markSeen preserve invocation order', () async {
    final item = (await repository.reconcile(
      period: '2026-10',
      freshClaims: [_claim(period: '2026-10')],
    ))
        .single;

    await Future.wait([
      repository.moveToLater(item.key),
      repository.markSeen(item.key),
    ]);

    expect(
      (await repository.readPeriod('2026-10')).single.state,
      TrendsInboxState.moved,
    );
  });

  test('reconcile retains its period and the previous 12 months', () async {
    final now = DateTime.now();
    final periods = [
      for (var monthsBack = AppConstants.trendsInboxRetentionMonths + 2;
          monthsBack >= 0;
          monthsBack--)
        _periodFor(DateTime(now.year, now.month - monthsBack)),
    ];
    for (final period in periods) {
      await repository.reconcile(
        period: period,
        freshClaims: [_claim(period: period)],
      );
    }

    final currentPeriod = periods.last;
    await repository.reconcile(
      period: currentPeriod,
      freshClaims: [_claim(period: currentPeriod)],
    );

    expect(
      (await repository.readAll()).map((item) => item.insight.period).toSet(),
      periods.skip(2).toSet(),
    );
  });

  test('corrupt and unknown-version JSON is preserved in backup metadata',
      () async {
    const raw = '{"v":9,"items":{"keep":"raw"}}';
    await database.into(database.modelMeta).insert(
          ModelMetaCompanion.insert(
            key: trendsInboxModelMetaKey,
            value: raw,
          ),
        );

    await repository.reconcile(
      period: '2026-10',
      freshClaims: [_claim(period: '2026-10')],
    );

    final backup = await (database.select(database.modelMeta)
          ..where((row) => row.key.equals(trendsInboxBackupMetaKey)))
        .getSingleOrNull();
    expect(backup?.value, raw);
  });

  test('malformed JSON is copied to backup before reconciliation repairs it',
      () async {
    const raw = '{"v":1,"items":';
    await database.into(database.modelMeta).insert(
          ModelMetaCompanion.insert(
            key: trendsInboxModelMetaKey,
            value: raw,
          ),
        );

    await repository.reconcile(
      period: '2026-10',
      freshClaims: [_claim(period: '2026-10')],
    );

    final backup = await (database.select(database.modelMeta)
          ..where((row) => row.key.equals(trendsInboxBackupMetaKey)))
        .getSingleOrNull();
    expect(backup?.value, raw);
  });

  test('cleared inbox item maps to the existing claim dismissal bit', () async {
    final insight = _claim(period: '2026-10');
    await database.into(database.insights).insert(
          InsightsCompanion.insert(
            id: insight.id,
            period: insight.period,
            kind: insight.kind,
            payloadJson: insight.payloadJson,
          ),
        );
    final items = await repository.reconcile(
      period: '2026-10',
      freshClaims: [insight],
    );

    await repository.clear(items.single.key);

    final row = await (database.select(database.insights)
          ..where((insight) => insight.id.equals(items.single.insight.id)))
        .getSingleOrNull();
    expect(row?.dismissed, isTrue);
    expect(
      (await repository.readPeriod('2026-10')).single.state,
      TrendsInboxState.cleared,
    );
  });

  test('claim identity rejects malformed claims', () async {
    final malformed = Insight(
      id: 'invalid',
      period: '2026-10',
      kind: 'not_supported',
      payloadJson: jsonEncode({'body': 'not claim evidence'}),
      dismissed: false,
    );
    final items = await repository.reconcile(
      period: '2026-10',
      freshClaims: [malformed],
    );

    expect(items, isEmpty);
  });
}

String _periodFor(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}';

Insight _claim({
  String kind = 'category_delta',
  required String period,
  double currentTotal = 120,
}) {
  const categoryId = 'food';
  final id = '$kind:$period:$categoryId:INR';
  final claim = <String, Object?>{
    'v': 1,
    'calc': '$kind@1',
    'claim_id': id,
    'basis': 'observed',
    'scope': kind == 'category_delta'
        ? {
            'category_id': categoryId,
            'currency_code': 'INR',
            'currency_symbol': '₹',
          }
        : {
            'category_ids': [categoryId],
            'currency_code': 'INR',
            'currency_symbol': '₹',
          },
    'window': {
      'current': ['$period-01', '$period-15'],
      if (kind == 'category_delta') 'previous': ['$period-01', '$period-15'],
      'partial': true,
    },
    'metrics': kind == 'category_delta'
        ? {
            'current_total': currentTotal,
            'previous_total': 100.0,
            'delta_fraction': (currentTotal - 100) / 100,
          }
        : {'total': currentTotal},
    'evidence': {
      'ids': ['transaction-1'],
      'total_count': 1,
      'truncated': false,
    },
    'coverage': {
      'rows': 1,
      'unreviewed': 0,
      'unknown_currency': 0,
      'excluded': {
        'not_settled': 0,
        'owned_transfer': 0,
        'analytics_excluded': 0,
        'non_spending': 0,
        'credit': 0,
      },
    },
    'input_hash': '0123456789abcdef',
  };
  return Insight(
    id: id,
    period: period,
    kind: kind,
    payloadJson: jsonEncode({
      'claim': claim,
      'untrusted_text': 'raw SMS must never enter the inbox snapshot',
    }),
    dismissed: false,
  );
}

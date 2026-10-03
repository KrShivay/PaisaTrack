import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/sms_backfill.dart';
import 'package:paisatrack/capture/sms_provenance_relinker.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/raw_sms.dart';

class _FakeInboxReader implements SmsInboxReader {
  _FakeInboxReader(this.pages);

  final List<List<RawSms>> pages;
  int reads = 0;

  @override
  Future<SmsInboxPage> readPage({
    SmsInboxCursor? before,
    required int limit,
  }) async {
    final index = before?.beforeId ?? 0;
    reads++;
    final hasMore = index + 1 < pages.length;
    return SmsInboxPage(
      messages: pages[index],
      nextCursor: hasMore
          ? SmsInboxCursor(beforeEpochMillis: 0, beforeId: index + 1)
          : null,
    );
  }
}

void main() {
  late AppDatabase database;
  final receivedAt = DateTime.utc(2026, 6, 1, 9);

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  RawSms sms(String id, String body) =>
      RawSms(id: id, sender: 'VK-HDFCBK', body: body, receivedAt: receivedAt);

  String evidenceFor(String body, String verbatim) {
    final start = body.indexOf(verbatim);
    return jsonEncode([
      {
        'field': 'amount',
        'start': start,
        'end': start + verbatim.length,
        'verbatim': verbatim,
        'extractor': 'template',
      },
    ]);
  }

  Future<void> insertTransaction(
    String smsId, {
    String? evidenceJson,
    String parseSource = 'template',
    String? categoryId,
  }) {
    return database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_$smsId',
            ts: receivedAt.millisecondsSinceEpoch,
            amount: 250,
            direction: 'debit',
            channel: 'upi',
            parseSource: parseSource,
            confidenceJson: '{}',
            evidenceJson: Value(evidenceJson),
            categoryId: Value(categoryId),
            status: 'confirmed',
            createdAt: receivedAt,
            updatedAt: receivedAt,
          ),
        );
  }

  test('re-links exact matches and skips and counts the rest', () async {
    const matchBody = 'Rs.250.00 debited from a/c XX1234 to payzomato@hdfcbank';
    const changedBody = 'Rs.999.00 debited from a/c XX1234 to someone@ybl';
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: 'food',
            name: 'Food',
            icon: 'restaurant',
            isSpending: true,
            sortOrder: 1,
            isUserCreated: false,
          ),
        );
    await insertTransaction(
      '101',
      evidenceJson: evidenceFor(matchBody, 'Rs.250.00'),
      categoryId: 'food',
    );
    // The provider id now points at a different message (e.g. a restored
    // inbox): evidence does not match, so it is skipped.
    await insertTransaction(
      '102',
      evidenceJson: evidenceFor(matchBody, 'Rs.250.00'),
    );
    // No stored evidence: cannot be verified deterministically.
    await insertTransaction('103');
    // Same provider id twice in the inbox: ambiguous.
    await insertTransaction(
      '104',
      evidenceJson: evidenceFor(matchBody, 'Rs.250.00'),
    );
    // Not in the inbox any more.
    await insertTransaction(
      '105',
      evidenceJson: evidenceFor(matchBody, 'Rs.250.00'),
    );
    // Manual rows never came from an SMS.
    await insertTransaction('106', parseSource: 'manual');

    final reader = _FakeInboxReader([
      [sms('101', matchBody), sms('102', changedBody), sms('103', matchBody)],
      [sms('104', matchBody), sms('104', matchBody), sms('999', matchBody)],
    ]);
    final relinker = SmsProvenanceRelinker(database: database, reader: reader);
    final before = await database.select(database.transactions).get();

    final result = await relinker.run();

    expect(result.relinked, 1);
    expect(result.skippedAmbiguous, 3);
    expect(result.notFound, 1);
    final rows = {
      for (final row in await database.select(database.transactions).get())
        row.id: row,
    };
    expect(rows['txn_101']!.smsId, '101');
    for (final id in ['102', '103', '104', '105', '106']) {
      expect(rows['txn_$id']!.smsId, isNull, reason: id);
    }
    // Never changes amounts, categories, or the row count.
    expect(rows.length, before.length);
    for (final original in before) {
      expect(rows[original.id]!.amount, original.amount);
      expect(rows[original.id]!.categoryId, original.categoryId);
      expect(rows[original.id]!.updatedAt, original.updatedAt);
    }
    final raw = await database.select(database.rawSms).get();
    expect(raw.map((row) => row.id), ['101']);
    expect(raw.single.body, matchBody);
    expect(raw.single.processed, isTrue);

    // Idempotent: a second run finds nothing new to link.
    final again = await relinker.run();
    expect(again.relinked, 0);
    expect((await database.select(database.rawSms).get()).length, 1);
  });

  test('does not read the inbox when no provenance is missing', () async {
    final reader = _FakeInboxReader([
      [sms('1', 'Rs.1 debited')],
    ]);

    final result =
        await SmsProvenanceRelinker(database: database, reader: reader).run();

    expect(result.relinked, 0);
    expect(reader.reads, 0);
  });

  test('respects paused senders, raw-row conflicts, and joins a running run',
      () async {
    const body = 'Rs.250.00 debited from a/c XX1234 to payzomato@hdfcbank';
    final evidence = evidenceFor(body, 'Rs.250.00');
    await insertTransaction('201', evidenceJson: evidence);
    await insertTransaction('202', evidenceJson: evidence);
    await insertTransaction('203', evidenceJson: evidence);
    // An unlinked raw row with the same id but a different body conflicts.
    await database.into(database.rawSms).insert(
          RawSmsCompanion.insert(
            id: '202',
            sender: 'VK-HDFCBK',
            body: 'A different retained body',
            receivedAt: receivedAt,
            purgeAfter: receivedAt,
          ),
        );
    final reader = _FakeInboxReader([
      [
        sms('201', body),
        sms('202', body),
        RawSms(
          id: '203',
          sender: 'VK-BLOCKD',
          body: body,
          receivedAt: receivedAt,
        ),
      ],
    ]);
    final relinker = SmsProvenanceRelinker(
      database: database,
      reader: reader,
      isSenderPaused: (sender) => sender == 'VK-BLOCKD',
    );

    final first = relinker.run();
    final second = relinker.run();
    expect(identical(first, second), isTrue);
    final result = await first;

    expect(reader.reads, 1);
    expect(result.relinked, 1);
    expect(result.skippedAmbiguous, 1);
    expect(result.notFound, 1);
    final raw = {
      for (final row in await database.select(database.rawSms).get())
        row.id: row.body,
    };
    expect(raw, {'201': body, '202': 'A different retained body'});
  });

  test('does nothing while capture is paused', () async {
    const body = 'Rs.250.00 debited';
    await insertTransaction(
      '301',
      evidenceJson: evidenceFor(body, 'Rs.250.00'),
    );
    final reader = _FakeInboxReader([
      [sms('301', body)],
    ]);

    final result = await SmsProvenanceRelinker(
      database: database,
      reader: reader,
      isCapturePaused: () => true,
    ).run();

    expect(result.relinked, 0);
    expect(reader.reads, 0);
  });
}

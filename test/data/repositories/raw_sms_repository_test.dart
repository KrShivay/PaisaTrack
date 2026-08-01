import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/parser_version.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/raw_sms_repository.dart';

void main() {
  test('summarizes only active allowlisted failures without raw content',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.utc(2026, 8, 2, 12);

    Future<void> insert(
      String id, {
      required String reason,
      required DateTime purgeAfter,
      bool processed = false,
    }) {
      return database.into(database.rawSms).insert(
            RawSmsCompanion.insert(
              id: id,
              sender: 'synthetic-sender',
              body: 'synthetic body must not be returned',
              receivedAt: now,
              processed: Value(processed),
              failureReason: Value(reason),
              purgeAfter: purgeAfter,
            ),
          );
    }

    await insert(
      'sms_unparsed',
      reason: SmsFailureReason.unparsed,
      purgeAfter: now.add(const Duration(days: 1)),
    );
    await insert(
      'sms_error',
      reason: SmsFailureReason.processingError,
      purgeAfter: now.add(const Duration(days: 1)),
    );
    await insert(
      'sms_expired',
      reason: SmsFailureReason.unparsed,
      purgeAfter: now.subtract(const Duration(seconds: 1)),
    );
    await insert(
      'sms_processed',
      reason: SmsFailureReason.processingError,
      purgeAfter: now.add(const Duration(days: 1)),
      processed: true,
    );
    await insert(
      'sms_unknown_reason',
      reason: 'unknown_reason',
      purgeAfter: now.add(const Duration(days: 1)),
    );

    final summary =
        await RawSmsRepository(database).watchRetainedFailures(now: now).first;

    expect(summary.total, 2);
    expect(summary.countFor(SmsFailureReason.unparsed), 1);
    expect(summary.countFor(SmsFailureReason.processingError), 1);
    expect(
      summary.reasonCounts.keys,
      containsAll([
        SmsFailureReason.unparsed,
        SmsFailureReason.processingError,
      ]),
    );
  });
}

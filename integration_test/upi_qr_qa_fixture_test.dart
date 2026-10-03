import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paisatrack/core/platform/recovery_qa_identity.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/settings/app_settings.dart';
import 'package:path_provider/path_provider.dart';

import 'recovery_qa_fixture_support.dart';

const _transactionId = 't199_upi_qr_qa_transaction';
const _counterpartyVpa = 'synthetic.qr@upi';
const _amount = 123.45;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('prepares a synthetic transaction for UPI QR device QA', () async {
    // This must remain the first platform or filesystem operation.
    await verifyRecoveryQaIdentity();

    final directory = await getApplicationDocumentsDirectory();
    final settingsStore = AppSettingsStore(directory);
    final settings = await settingsStore.read();
    await settingsStore.write(settings.copyWith(onboardingCompleted: true));
    expect((await settingsStore.read()).onboardingCompleted, isTrue);

    final container = ProviderContainer();
    AppDatabase? database;
    try {
      final openedDatabase = await container.read(appDatabaseProvider.future);
      database = openedDatabase;
      final existingTransaction =
          await (openedDatabase.select(openedDatabase.transactions)
                ..where((row) => row.id.equals(_transactionId)))
              .getSingleOrNull();
      expect(
        existingTransaction,
        isNull,
        reason: 'Fixture rows are never reset or overwritten.',
      );

      final now = DateTime.now().toUtc();
      await openedDatabase.into(openedDatabase.transactions).insert(
            TransactionsCompanion.insert(
              id: _transactionId,
              ts: now.millisecondsSinceEpoch,
              amount: _amount,
              currencyCode: const Value('INR'),
              currencySymbol: const Value('₹'),
              direction: 'debit',
              channel: 'upi',
              merchantRaw: const Value('Synthetic UPI QR QA'),
              description: const Value('Synthetic UPI QR QA transaction'),
              parseSource: 'generic',
              confidenceJson: '{}',
              status: 'needs_review',
              counterpartyVpa: const Value(_counterpartyVpa),
              evidenceJson: const Value(
                '{"fixture":"T-199","source":"synthetic"}',
              ),
              createdAt: now,
              updatedAt: now,
            ),
          );

      final transaction =
          await (openedDatabase.select(openedDatabase.transactions)
                ..where((row) => row.id.equals(_transactionId)))
              .getSingle();
      expect(transaction.counterpartyVpa, _counterpartyVpa);
      expect(transaction.status, 'needs_review');
      expect(transaction.amount, _amount);
      expect(transaction.currencyCode, 'INR');
      expect(transaction.currencySymbol, '₹');

      emitRecoveryQaMarker('UPI_QR_QA_PREPARED', {
        'transactionId': transaction.id,
        'merchantRaw': transaction.merchantRaw,
        'counterpartyVpa': transaction.counterpartyVpa,
        'channel': transaction.channel,
        'direction': transaction.direction,
        'amount': transaction.amount,
        'currencyCode': transaction.currencyCode,
        'currencySymbol': transaction.currencySymbol,
        'status': transaction.status,
        'synthetic': true,
        'smsId': transaction.smsId,
      });
    } finally {
      if (database != null) await closeAppDatabase(database);
      container.dispose();
    }
  });
}

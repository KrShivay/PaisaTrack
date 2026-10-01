import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paisatrack/core/constants.dart';
import 'package:paisatrack/core/platform/recovery_qa_identity.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/enrichment/source_currency_repair_service.dart';
import 'package:paisatrack/features/settings/app_settings.dart';
import 'package:path_provider/path_provider.dart';

import 'currency_repair_qa_fixture_support.dart';
import 'recovery_qa_fixture_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('prepares a normal synthetic source-currency repair database', () async {
    // This identity attestation must precede files, keys, and providers.
    await verifyRecoveryQaIdentity();

    final directory = await getApplicationDocumentsDirectory();
    final settingsStore = AppSettingsStore(directory);

    final container = ProviderContainer();
    AppDatabase? database;
    try {
      final openedDatabase = await container.read(appDatabaseProvider.future);
      database = openedDatabase;
      final existingTransaction =
          await (openedDatabase.select(openedDatabase.transactions)
                ..where((row) => row.id.equals(currencyRepairQaTransactionId)))
              .getSingleOrNull();
      expect(
        existingTransaction,
        isNull,
        reason:
            'Use a fresh synthetic QA package; fixture rows are never reset.',
      );

      final existingSource =
          await (openedDatabase.select(openedDatabase.paymentSources)
                ..where((row) => row.id.equals(currencyRepairQaSourceId)))
              .getSingleOrNull();
      expect(existingSource, isNull);

      final settings = await settingsStore.read();
      await settingsStore.write(settings.copyWith(onboardingCompleted: true));

      final now = DateTime.now().toUtc();
      final receivedAt = now.subtract(const Duration(days: 1));
      final purgeAfter = receivedAt.add(
        const Duration(days: AppConstants.rawSmsRetentionDays),
      );
      const smsId = 't193_currency_repair_qa_sms';
      await openedDatabase.into(openedDatabase.paymentSources).insert(
            PaymentSourcesCompanion.insert(
              id: currencyRepairQaSourceId,
              kind: 'card',
              maskedIdentifier: 'xx4242',
              nickname: const Value('Synthetic Currency QA'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await openedDatabase.into(openedDatabase.rawSms).insert(
            RawSmsCompanion.insert(
              id: smsId,
              sender: 'XX-BANK',
              body: currencyRepairQaBody,
              receivedAt: receivedAt,
              purgeAfter: purgeAfter,
            ),
          );
      await openedDatabase.into(openedDatabase.transactions).insert(
            TransactionsCompanion.insert(
              id: currencyRepairQaTransactionId,
              ts: now.millisecondsSinceEpoch,
              amount: currencyRepairQaAmount,
              direction: 'debit',
              channel: 'card',
              paymentSourceId: const Value(currencyRepairQaSourceId),
              merchantRaw: const Value('Synthetic Currency QA'),
              description: const Value('Synthetic Currency QA purchase'),
              parseSource: 'generic',
              smsId: const Value(smsId),
              confidenceJson: '{}',
              evidenceJson: Value(currencyRepairQaEvidenceJson()),
              status: 'confirmed',
              createdAt: now,
              updatedAt: now,
            ),
          );

      final transaction =
          await (openedDatabase.select(openedDatabase.transactions)
                ..where((row) => row.id.equals(currencyRepairQaTransactionId)))
              .getSingle();
      expect(transaction.currencyCode, isNull);
      expect(transaction.currencySymbol, isNull);
      final preview = await SourceCurrencyRepairService(openedDatabase)
          .preview(currencyRepairQaTransactionId);
      expect(preview, isNotNull);
      expect(preview!.currencyToken, 'Rs.');
      expect(preview.amountPaise, 123450);

      emitRecoveryQaMarker('CURRENCY_REPAIR_QA_PREPARED', {
        'transactionId': currencyRepairQaTransactionId,
        'paymentSourceId': currencyRepairQaSourceId,
        'rawSmsId': smsId,
        'amount': currencyRepairQaAmount,
        'expectedApplied': {'currencyCode': 'INR', 'currencySymbol': '₹'},
        'expectedUndone': {'currencyCode': null, 'currencySymbol': null},
        'eligiblePreview': true,
        'receivedAt': receivedAt.toIso8601String(),
        'purgeAfter': purgeAfter.toIso8601String(),
        'smsPermissionsRequested': false,
      });
    } finally {
      if (database != null) await closeAppDatabase(database);
      container.dispose();
    }
  });
}

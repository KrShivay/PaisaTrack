import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paisatrack/core/platform/recovery_qa_identity.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/enrichment/source_currency_repair_service.dart';

import 'currency_repair_qa_fixture_support.dart';
import 'recovery_qa_fixture_support.dart';

const _expectedState = String.fromEnvironment(
  'CURRENCY_REPAIR_QA_EXPECTED_STATE',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'verifies source-currency repair state through production provider',
    () async {
      await verifyRecoveryQaIdentity();
      expect(
        {'applied', 'undone'},
        contains(_expectedState),
        reason:
            'Set --dart-define=CURRENCY_REPAIR_QA_EXPECTED_STATE=applied|undone',
      );

      final container = ProviderContainer();
      AppDatabase? database;
      try {
        final openedDatabase = await container.read(appDatabaseProvider.future);
        database = openedDatabase;
        final transaction = await (openedDatabase.select(
          openedDatabase.transactions,
        )..where((row) => row.id.equals(currencyRepairQaTransactionId)))
            .getSingle();
        final preview = await SourceCurrencyRepairService(
          openedDatabase,
        ).preview(currencyRepairQaTransactionId);

        const expectedApplied = _expectedState == 'applied';
        expect(transaction.amount, currencyRepairQaAmount);
        if (expectedApplied) {
          expect(transaction.currencyCode, 'INR');
          expect(transaction.currencySymbol, '₹');
          expect(preview, isNull);
        } else {
          expect(transaction.currencyCode, isNull);
          expect(transaction.currencySymbol, isNull);
          expect(preview, isNotNull);
        }

        emitRecoveryQaMarker('CURRENCY_REPAIR_QA_VERIFIED', {
          'transactionId': transaction.id,
          'expectedState': _expectedState,
          'currencyCode': transaction.currencyCode,
          'currencySymbol': transaction.currencySymbol,
          'amount': transaction.amount,
          'repairHistory': 'not persisted by SourceCurrencyRepairService',
          'undoState': expectedApplied
              ? 'process-local UI undo is not available in this fresh process'
              : 'not-applied',
          'sourcePreviewAvailable': preview != null,
        });
      } finally {
        if (database != null) await closeAppDatabase(database);
        container.dispose();
      }
    },
  );
}

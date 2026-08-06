import '../../enrichment/payee_identity_key.dart';
import '../db/database.dart';

/// Maintains the rebuildable normalized evidence index used by payee SQL.
class PayeeEvidenceRepository {
  const PayeeEvidenceRepository(this._database);

  final AppDatabase _database;

  Future<void> replaceForTransaction({
    required String transactionId,
    String? merchantRaw,
    String? counterpartyVpa,
  }) async {
    await (_database.delete(_database.payeeEvidence)
          ..where((row) => row.transactionId.equals(transactionId)))
        .go();
    final rows = companionsFor(
      transactionId: transactionId,
      merchantRaw: merchantRaw,
      counterpartyVpa: counterpartyVpa,
    );
    if (rows.isEmpty) return;
    await _database.batch((batch) {
      batch.insertAll(_database.payeeEvidence, rows);
    });
  }

  /// Rebuilds all derived rows from authoritative transaction evidence.
  Future<void> rebuild() async {
    final transactions = await _database.select(_database.transactions).get();
    final rows = <PayeeEvidenceCompanion>[];
    for (final transaction in transactions) {
      rows.addAll(
        companionsFor(
          transactionId: transaction.id,
          merchantRaw: transaction.merchantRaw,
          counterpartyVpa: transaction.counterpartyVpa,
        ),
      );
    }
    await _database.delete(_database.payeeEvidence).go();
    if (rows.isNotEmpty) {
      await _database.batch((batch) {
        batch.insertAll(_database.payeeEvidence, rows);
      });
    }
  }

  static List<PayeeEvidenceCompanion> companionsFor({
    required String transactionId,
    String? merchantRaw,
    String? counterpartyVpa,
  }) {
    final rows = <PayeeEvidenceCompanion>[];
    _add(
      rows,
      transactionId: transactionId,
      evidenceType: 'merchant_raw',
      value: merchantRaw,
    );
    _add(
      rows,
      transactionId: transactionId,
      evidenceType: 'counterparty_vpa',
      value: counterpartyVpa,
    );
    return rows;
  }

  static void _add(
    List<PayeeEvidenceCompanion> rows, {
    required String transactionId,
    required String evidenceType,
    required String? value,
  }) {
    final displayValue = value?.trim();
    if (displayValue == null || displayValue.isEmpty) return;
    final normalizedKey = PayeeIdentityKey.normalize(displayValue);
    if (normalizedKey.isEmpty) return;
    rows.add(
      PayeeEvidenceCompanion.insert(
        transactionId: transactionId,
        evidenceType: evidenceType,
        normalizedKey: normalizedKey,
        displayValue: displayValue,
      ),
    );
  }
}

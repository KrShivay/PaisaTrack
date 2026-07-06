import '../core/constants.dart';
import '../data/db/database.dart';
import '../data/models/normalized_transaction_record.dart';

/// Detects when a newly parsed transaction is a cross-source echo of an
/// already-stored one — e.g. a bank debit alert and a wallet/UPI app's own
/// notification for the same payment (T-025).
///
/// Same-SMS idempotency (re-ingesting one message) is already handled by the
/// deterministic `txn_<smsId>` primary key in `SmsIngestor`; this only covers
/// two *different* SMS describing the same real-world transaction.
class DuplicateSuppressor {
  const DuplicateSuppressor({
    this.window = const Duration(
      minutes: AppConstants.duplicatePairWindowMinutes,
    ),
    this.amountTolerance = 0.005,
  });

  /// Max gap between the two SMS timestamps to still consider them paired.
  final Duration window;

  /// Absolute rupee tolerance when comparing amounts (guards float rounding).
  final double amountTolerance;

  /// True when [candidate] and [existing] look like two notifications for
  /// the same payment: same direction, matching amount, timestamps within
  /// [window], and a matching counterparty (UPI ref id, VPA, or merchant
  /// text).
  bool isDuplicate(
    NormalizedTransactionRecord candidate,
    Transaction existing,
  ) {
    if (existing.isDeleted) return false;
    if (existing.direction != candidate.direction.wireName) return false;
    if ((existing.amount - candidate.amount).abs() > amountTolerance) {
      return false;
    }

    final existingTs = DateTime.fromMillisecondsSinceEpoch(
      existing.ts,
      isUtc: true,
    );
    if (candidate.ts.toUtc().difference(existingTs).abs() > window) {
      return false;
    }

    if (_sameRefId(candidate.refId, existing.refId)) {
      return true;
    }
    return _sameCounterparty(
      _counterpartyKey(candidate.counterpartyVpa, candidate.merchantRaw),
      _counterpartyKey(null, existing.merchantRaw),
    );
  }

  bool _sameRefId(String? a, String? b) {
    if (a == null || b == null || a.isEmpty || b.isEmpty) return false;
    return a == b;
  }

  bool _sameCounterparty(String? a, String? b) {
    if (a == null || b == null) return false;
    if (a.length < 3 || b.length < 3) return false;
    return a == b || a.contains(b) || b.contains(a);
  }

  /// Reduces a VPA (preferred) or merchant string to an uppercase
  /// alphanumeric key so e.g. `amazon@ybl` and `Amazon Pay India` overlap.
  String? _counterpartyKey(String? vpa, String? merchantRaw) {
    final raw = (vpa != null && vpa.isNotEmpty) ? vpa : merchantRaw;
    if (raw == null || raw.isEmpty) return null;
    final localPart = raw.split('@').first;
    final normalized = localPart
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return normalized.isEmpty ? null : normalized;
  }
}

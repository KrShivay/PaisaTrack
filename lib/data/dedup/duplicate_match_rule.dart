import '../db/database.dart';

/// Pure cross-source-echo matching rule (direction, amount, time window,
/// ref id, counterparty key), shared by live ingestion's
/// `DuplicateSuppressor` (capture layer) and the v1->v2 migration backfill
/// (ADR 0003), so both use identical semantics.
class DuplicateMatchRule {
  const DuplicateMatchRule({
    required this.window,
    required this.amountTolerance,
  });

  /// Max gap between the two timestamps to still consider them paired.
  final Duration window;

  /// Absolute rupee tolerance when comparing amounts (guards float rounding).
  final double amountTolerance;

  /// True when a candidate transaction (given as primitive fields) and
  /// [existing] look like two notifications for the same real-world payment.
  bool matches({
    required String direction,
    required double amount,
    required DateTime ts,
    required String? refId,
    required String? counterpartyKey,
    required Transaction existing,
  }) {
    if (existing.direction != direction) return false;
    if ((existing.amount - amount).abs() > amountTolerance) return false;

    final existingTs = DateTime.fromMillisecondsSinceEpoch(
      existing.ts,
      isUtc: true,
    );
    if (ts.toUtc().difference(existingTs).abs() > window) return false;

    if (_sameRefId(refId, existing.refId)) return true;
    return _sameCounterparty(
      counterpartyKey,
      counterpartyKeyOf(existing.counterpartyVpa, existing.merchantRaw),
    );
  }

  static bool _sameRefId(String? a, String? b) {
    if (a == null || b == null || a.isEmpty || b.isEmpty) return false;
    return a == b;
  }

  static bool _sameCounterparty(String? a, String? b) {
    if (a == null || b == null) return false;
    if (a.length < 3 || b.length < 3) return false;
    return a == b || a.contains(b) || b.contains(a);
  }

  /// Reduces a VPA (preferred) or merchant string to an uppercase
  /// alphanumeric key so e.g. `amazon@ybl` and `Amazon Pay India` overlap.
  static String? counterpartyKeyOf(String? vpa, String? merchantRaw) {
    final raw = (vpa != null && vpa.isNotEmpty) ? vpa : merchantRaw;
    if (raw == null || raw.isEmpty) return null;
    final localPart = raw.split('@').first;
    final normalized = localPart
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return normalized.isEmpty ? null : normalized;
  }
}

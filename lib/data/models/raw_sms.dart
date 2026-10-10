/// Raw SMS captured from Android before parsing.
///
/// Instances can contain highly sensitive data. Keep them local, avoid logging
/// `body`, and enforce retention through the database layer.
class RawSms {
  const RawSms({
    required this.id,
    required this.sender,
    required this.body,
    required this.receivedAt,
    this.legacyId,
  });

  final String id;
  final String sender;

  /// Full SMS body exactly as received from Android.
  final String body;

  /// Device receive time used as a parser fallback when SMS text omits a date.
  final DateTime receivedAt;

  /// Prior receipt-time identity for inbox rows stored before DATE_SENT was
  /// used as the canonical capture timestamp.
  final String? legacyId;

  /// The canonical identity and its one bounded, exact-content compatibility
  /// alias. This is transient capture metadata, not a persisted model field.
  Set<String> get identityIds => {
        id,
        if (legacyId != null && legacyId != id) legacyId!,
      };
}

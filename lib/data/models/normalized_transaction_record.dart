/// Canonical transaction shape produced by parsers before database enrichment.
///
/// This is intentionally close to the frozen record contract in the plan. Raw
/// SMS text must not be added here; sensitive source material stays in raw SMS
/// storage with retention controls.
class NormalizedTransactionRecord {
  const NormalizedTransactionRecord({
    required this.amount,
    required this.direction,
    required this.channel,
    required this.merchantRaw,
    required this.counterpartyVpa,
    required this.accountHint,
    required this.balanceAfter,
    required this.refId,
    required this.ts,
    required this.parseSource,
    required this.parseConfidence,
    this.templateId,
    this.templateProvenance,
    this.evidence,
  });

  final double amount;
  int get amountPaise => (amount * 100).round();
  final TransactionDirection direction;
  final TransactionChannel channel;
  final String? merchantRaw;
  final String? counterpartyVpa;
  final String? accountHint;
  final double? balanceAfter;
  final String? refId;
  final DateTime ts;
  final ParseSource parseSource;

  /// Parser confidence from 0.0 to 1.0.
  final double parseConfidence;

  /// Template identity retained for ingest provenance; omitted from the frozen
  /// parser wire contract and absent for non-template parse paths.
  final String? templateId;

  /// Fixture evidence tier associated with [templateId], when present.
  final String? templateProvenance;

  /// Verifying span evidence linking record values back to raw source text.
  final List<FieldEvidence>? evidence;

  /// Returns this record with updated evidence.
  NormalizedTransactionRecord withEvidence(List<FieldEvidence> evidence) {
    return NormalizedTransactionRecord(
      amount: amount,
      direction: direction,
      channel: channel,
      merchantRaw: merchantRaw,
      counterpartyVpa: counterpartyVpa,
      accountHint: accountHint,
      balanceAfter: balanceAfter,
      refId: refId,
      ts: ts,
      parseSource: parseSource,
      parseConfidence: parseConfidence,
      templateId: templateId,
      templateProvenance: templateProvenance,
      evidence: evidence,
    );
  }

  /// Returns this record with a different parser confidence.
  NormalizedTransactionRecord withParseConfidence(double confidence) {
    return NormalizedTransactionRecord(
      amount: amount,
      direction: direction,
      channel: channel,
      merchantRaw: merchantRaw,
      counterpartyVpa: counterpartyVpa,
      accountHint: accountHint,
      balanceAfter: balanceAfter,
      refId: refId,
      ts: ts,
      parseSource: parseSource,
      parseConfidence: confidence,
      templateId: templateId,
      templateProvenance: templateProvenance,
      evidence: evidence,
    );
  }

  /// Serializes using stable wire names for fixtures and future interchange.
  Map<String, Object?> toJson({bool includeEvidence = false}) {
    return {
      'amount': amount,
      'direction': direction.wireName,
      'channel': channel.wireName,
      'merchant_raw': merchantRaw,
      'counterparty_vpa': counterpartyVpa,
      'account_hint': accountHint,
      'balance_after': balanceAfter,
      'ref_id': refId,
      'ts': ts.millisecondsSinceEpoch,
      'parse_source': parseSource.wireName,
      'parse_confidence': parseConfidence,
      if (includeEvidence && evidence != null)
        'evidence': evidence!.map((e) => e.toJson()).toList(),
    };
  }
}

/// Verifying span evidence linking a record value back to raw source text.
class FieldEvidence {
  const FieldEvidence({
    required this.field,
    required this.start,
    required this.end,
    required this.verbatim,
    required this.extractor,
  });

  final String field;
  final int start;
  final int end;
  final String verbatim;
  final String extractor;

  Map<String, Object?> toJson() {
    return {
      'field': field,
      'start': start,
      'end': end,
      'verbatim': verbatim,
      'extractor': extractor,
    };
  }

  factory FieldEvidence.fromJson(Map<String, Object?> json) {
    return FieldEvidence(
      field: json['field']! as String,
      start: (json['start']! as num).toInt(),
      end: (json['end']! as num).toInt(),
      verbatim: json['verbatim']! as String,
      extractor: json['extractor']! as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FieldEvidence &&
          runtimeType == other.runtimeType &&
          field == other.field &&
          start == other.start &&
          end == other.end &&
          verbatim == other.verbatim &&
          extractor == other.extractor;

  @override
  int get hashCode => Object.hash(field, start, end, verbatim, extractor);
}

/// Direction of money movement from the user's perspective.
enum TransactionDirection {
  debit,
  credit,
}

/// Stable wire names for transaction direction values.
extension TransactionDirectionWireName on TransactionDirection {
  String get wireName => name;
}

/// Payment channel inferred from SMS content.
enum TransactionChannel {
  upi,
  card,
  netbanking,
  atm,
  wallet,
  cash,
  unknown,
}

/// Stable wire names for transaction channel values.
extension TransactionChannelWireName on TransactionChannel {
  String get wireName => name;
}

/// Parser or workflow that produced the normalized record.
///
/// There is intentionally no cloud value: no cloud inference path exists
/// (ADR 0002 — all parsing runs on-device).
enum ParseSource {
  template,
  generic,
  localLlm,
  manual,
}

/// Stable wire names for parse source values.
extension ParseSourceWireName on ParseSource {
  String get wireName {
    return switch (this) {
      ParseSource.template => 'template',
      ParseSource.generic => 'generic',
      ParseSource.localLlm => 'local_llm',
      ParseSource.manual => 'manual',
    };
  }
}
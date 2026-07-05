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
  });

  final double amount;
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

  /// Serializes using stable wire names for fixtures and future interchange.
  Map<String, Object?> toJson() {
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
    };
  }
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
enum ParseSource {
  template,
  localLlm,
  cloud,
  manual,
}

/// Stable wire names for parse source values.
extension ParseSourceWireName on ParseSource {
  String get wireName {
    return switch (this) {
      ParseSource.template => 'template',
      ParseSource.localLlm => 'local_llm',
      ParseSource.cloud => 'cloud',
      ParseSource.manual => 'manual',
    };
  }
}

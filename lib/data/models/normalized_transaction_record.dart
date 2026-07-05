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
  final double parseConfidence;

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

enum TransactionDirection {
  debit,
  credit,
}

extension TransactionDirectionWireName on TransactionDirection {
  String get wireName => name;
}

enum TransactionChannel {
  upi,
  card,
  netbanking,
  atm,
  wallet,
  cash,
  unknown,
}

extension TransactionChannelWireName on TransactionChannel {
  String get wireName => name;
}

enum ParseSource {
  template,
  localLlm,
  cloud,
  manual,
}

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

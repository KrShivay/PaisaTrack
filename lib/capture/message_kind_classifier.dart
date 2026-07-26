import 'dart:convert';

/// Represents the classification of a financial or transactional SMS message.
enum MessageKind {
  settledDebit('settledDebit'),
  settledCredit('settledCredit'),
  pendingAuth('pendingAuth'),
  failed('failed'),
  reversal('reversal'),
  reminder('reminder'),
  mandate('mandate'),
  balance('balance'),
  statement('statement'),
  promo('promo'),
  otp('otp');

  const MessageKind(this.wireName);

  final String wireName;

  static MessageKind fromWireName(String name) {
    return MessageKind.values.firstWhere(
      (e) => e.wireName == name,
      orElse: () => MessageKind.settledDebit,
    );
  }
}

/// Deterministic cue-phrase classifier assigning exactly one [MessageKind]
/// to an SMS body before extraction.
class MessageKindClassifier {
  const MessageKindClassifier({
    required this.cues,
  });

  final Map<MessageKind, List<RegExp>> cues;

  /// Creates a classifier from a JSON string structured like `assets/seed/message_cues_in.json`.
  factory MessageKindClassifier.fromJson(String jsonString) {
    final map = jsonDecode(jsonString) as Map<String, Object?>;
    final cuesMap = map['cues'] as Map<String, Object?>? ?? {};
    final parsedCues = <MessageKind, List<RegExp>>{};

    for (final kind in MessageKind.values) {
      final list = cuesMap[kind.wireName] as List<Object?>? ?? [];
      final regExps = list
          .whereType<String>()
          .map((pattern) => RegExp(pattern, caseSensitive: false))
          .toList(growable: false);
      parsedCues[kind] = regExps;
    }

    return MessageKindClassifier(cues: parsedCues);
  }

  /// Classifies [body] into exactly one [MessageKind].
  MessageKind classify(String body) {
    // Priority order evaluation
    const evaluationOrder = [
      MessageKind.otp,
      MessageKind.failed,
      MessageKind.reversal,
      MessageKind.reminder,
      MessageKind.mandate,
      MessageKind.statement,
      MessageKind.balance,
      MessageKind.promo,
      MessageKind.pendingAuth,
      MessageKind.settledCredit,
      MessageKind.settledDebit,
    ];

    for (final kind in evaluationOrder) {
      final regExps = cues[kind];
      if (regExps == null) continue;
      for (final regExp in regExps) {
        if (regExp.hasMatch(body)) {
          return kind;
        }
      }
    }

    // Default fallback
    return MessageKind.settledDebit;
  }
}

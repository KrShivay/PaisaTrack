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
  otp('otp'),
  unknown('unknown');

  const MessageKind(this.wireName);

  final String wireName;

  static MessageKind fromWireName(String name) {
    return MessageKind.values.firstWhere(
      (e) => e.wireName == name,
      orElse: () => MessageKind.unknown,
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
    // Lifecycle and non-transactional cues always outrank payment wording.
    const protectedOrder = [
      MessageKind.otp,
      MessageKind.failed,
      MessageKind.reversal,
      MessageKind.reminder,
      MessageKind.mandate,
      MessageKind.statement,
      MessageKind.pendingAuth,
    ];

    for (final kind in protectedOrder) {
      if (kind == MessageKind.otp && _hasDetachedSecurityFooterOtp(body)) {
        continue;
      }
      if (kind == MessageKind.failed && _isFailedPaymentReturn(body)) {
        continue;
      }
      if (_matches(kind, body)) return kind;
    }

    final hasBalance = _matches(MessageKind.balance, body);
    final hasCredit = _matches(MessageKind.settledCredit, body);
    final hasDebit = _matches(MessageKind.settledDebit, body);
    final hasPromo = _matches(MessageKind.promo, body);

    // Reward copy often includes words such as "spent" and a currency
    // threshold. Any promotional footer can accompany a real payment, so let
    // only an amount plus an account/card movement sentence override it.
    if (hasPromo &&
        !((hasDebit &&
                _hasPromotionalPaymentOverride(
                  body,
                  credit: false,
                )) ||
            (hasCredit &&
                _hasPromotionalPaymentOverride(
                  body,
                  credit: true,
                )))) {
      return MessageKind.promo;
    }

    // Conflicting lifecycle direction cues are not resolved by arbitrary
    // enum order. Leave them for explicit review instead of inventing a side.
    if (hasCredit && hasDebit) return MessageKind.unknown;

    if (hasBalance) {
      if (hasCredit && _hasStrongPaymentEvent(body, credit: true)) {
        return MessageKind.settledCredit;
      }
      if (hasDebit && _hasStrongPaymentEvent(body, credit: false)) {
        return MessageKind.settledDebit;
      }
      return MessageKind.balance;
    }

    if (hasCredit) return MessageKind.settledCredit;
    if (hasDebit) return MessageKind.settledDebit;
    return MessageKind.unknown;
  }

  bool _matches(MessageKind kind, String body) =>
      (cues[kind]?.any(
            (regExp) => regExp.allMatches(body).any(
                  (match) => _hasWholeTokenBoundaries(body, match),
                ),
          ) ??
          false) ||
      (kind == MessageKind.pendingAuth &&
          _hasAffirmativeAuthorizationCue(body));

  bool _hasWholeTokenBoundaries(String body, RegExpMatch match) {
    if (match.start == match.end) return true;
    bool isWordCharacter(String value) => RegExp(r'^\w$').hasMatch(value);

    if (match.start > 0 &&
        isWordCharacter(body[match.start - 1]) &&
        isWordCharacter(body[match.start])) {
      return false;
    }
    if (match.end < body.length &&
        isWordCharacter(body[match.end - 1]) &&
        isWordCharacter(body[match.end])) {
      return false;
    }
    return true;
  }

  bool _hasAffirmativeAuthorizationCue(String body) {
    final normalizedBody = body.replaceAll(RegExp(r'[\r\n]+'), ' ');
    for (final clause in _splitClauses(normalizedBody)) {
      final normalized = clause.replaceAll(RegExp(r'\s+'), ' ');
      for (final match in RegExp(r'\bauthorized\b', caseSensitive: false)
          .allMatches(normalized)) {
        final start = (match.start - 64).clamp(0, match.start);
        final preceding = normalized.substring(start, match.start).trimRight();
        if (!_hasAuthorizationNegation(preceding)) return true;
      }
    }
    return false;
  }

  bool _hasAuthorizationNegation(String preceding) => RegExp(
        r"\b(?:not(?:\s+(?:yet|been)){0,2}|never(?:\s+been)?|cannot|can['’]t|(?:could|would|should)\s+not(?:\s+\w+){0,2}|(?:could|would|should)n['’]t|(?:has|have|had|was|were|is|are)\s+not(?:\s+(?:yet|been)){0,2}|(?:has|have|had|was|were|is|are)n['’]t(?:\s+been)?|unable\s+to)\s*$",
        caseSensitive: false,
      ).hasMatch(preceding);

  bool _hasDetachedSecurityFooterOtp(String body) {
    final clauses = _splitClauses(body);
    bool isSecurityFooter(String clause) => RegExp(
          r'^\s*(?:(?:never|do not)\s+share\b|if\b.*\b(?:unauthorized|not\s+authorized)\b)',
          caseSensitive: false,
        ).hasMatch(clause);

    final hasSecurityOtpFooter = clauses.any(
      (clause) => isSecurityFooter(clause) && _matches(MessageKind.otp, clause),
    );
    if (!hasSecurityOtpFooter) return false;

    final hasPrimaryOtpClause = clauses.any(
      (clause) =>
          !isSecurityFooter(clause) && _matches(MessageKind.otp, clause),
    );
    if (hasPrimaryOtpClause) return false;

    return clauses.any(
      (clause) =>
          !isSecurityFooter(clause) &&
          (_hasStrongPaymentEvent(clause, credit: true) ||
              _hasStrongPaymentEvent(clause, credit: false)),
    );
  }

  /// Returns a direction cue only when the SMS has exactly one settled side.
  /// Lifecycle labels (failed, pending, reversal) remain independent.
  MessageKind? settledDirectionCue(String body) {
    final hasCredit = _matches(MessageKind.settledCredit, body);
    final hasDebit = _matches(MessageKind.settledDebit, body);
    if (hasCredit == hasDebit) return null;
    return hasCredit ? MessageKind.settledCredit : MessageKind.settledDebit;
  }

  bool _hasStrongPaymentEvent(String body, {required bool credit}) {
    if (_hasStrongPaymentContext(body, credit: credit, allowPurchaseOf: true)) {
      return true;
    }

    final movement = credit
        ? r'(?:credited|received|deposited)'
        : r'(?:debited|withdrawn|charged|transferred|sent)';
    const amount = r'(?:\binr\b|\brs\.?|₹)\s*[\d,]+(?:\.\d{1,2})?';
    return RegExp(
      r'\b(?:a/c|account|card)\b.{0,35}\b' + movement + r'\b.{0,35}' + amount,
      caseSensitive: false,
    ).hasMatch(body);
  }

  bool _isFailedPaymentReturn(String body) {
    final failedUpiReason = RegExp(
      r'\bfor\s+(?:a\s+)?failed\s+(?:upi\s+)?(?:txn|transaction)\b',
      caseSensitive: false,
    );
    return _splitClauses(body).any(
      (clause) =>
          _hasStrongPaymentEvent(clause, credit: true) &&
          _hasAffirmativeCreditedBy(clause) &&
          failedUpiReason.hasMatch(clause),
    );
  }

  bool _hasAffirmativeCreditedBy(String clause) {
    final cue = RegExp(r'\bcredited\s+by\b', caseSensitive: false);
    for (final match in cue.allMatches(clause)) {
      final preceding = clause.substring(0, match.start);
      final boundedPreceding = preceding.length > 48
          ? preceding.substring(preceding.length - 48)
          : preceding;
      if (!RegExp(
        r"\b(?:no(?:\s+\w+){0,4}|not(?:\s+\w+){0,2}|never(?:\s+\w+){0,2}|cannot|can['’]t|couldn['’]t|could\s+not(?:\s+\w+){0,2}|hasn['’]t(?:\s+been)?|has\s+not(?:\s+\w+){0,2}|haven['’]t(?:\s+been)?|have\s+not(?:\s+\w+){0,2}|wasn['’]t|was\s+not|weren['’]t|were\s+not|isn['’]t|is\s+not|aren['’]t|are\s+not|unable\s+to)\b",
        caseSensitive: false,
      ).hasMatch(boundedPreceding)) {
        return true;
      }
    }
    return false;
  }

  bool _hasPromotionalPaymentOverride(
    String body, {
    required bool credit,
  }) {
    final amount = RegExp(
      r'(?:\binr\b|\brs\.?|₹)\s*[\d,]+(?:\.\d{1,2})?',
      caseSensitive: false,
    );
    final movement = credit
        ? RegExp(
            r'\b(?:credited|received|deposited)\b.{0,40}\b(?:to|into)\s+(?:your\s+)?(?:a/c|account|card)\b|\badded\s+to\s+(?:your\s+)?(?:a/c|account|card)\b',
            caseSensitive: false,
          )
        : RegExp(
            r'\b(?:debited|withdrawn|transferred|sent)\b.{0,40}\bfrom\s+(?:your\s+)?(?:a/c|account|card)\b|\bcharged\b.{0,40}\b(?:on|to)\s+(?:your\s+)?(?:a/c|account|card)\b',
            caseSensitive: false,
          );

    for (final clause in _splitClauses(body)) {
      final amounts = amount.allMatches(clause);
      final movements = movement.allMatches(clause);
      for (final amountMatch in amounts) {
        for (final movementMatch in movements) {
          final nearMovementStart =
              (amountMatch.start - movementMatch.start).abs() <= 24;
          final nearMovementEnd =
              (amountMatch.end - movementMatch.end).abs() <= 24;
          if (nearMovementStart || nearMovementEnd) return true;
        }
      }
    }
    return false;
  }

  List<String> _splitClauses(String body) {
    final clauses = <String>[];
    var start = 0;
    for (var i = 0; i < body.length; i++) {
      final char = body[i];
      if (char == '!' || char == '?' || char == ';' || char == '\n') {
        clauses.add(body.substring(start, i));
        start = i + 1;
        continue;
      }
      if (char != '.') continue;
      final isDecimal = i > 0 &&
          i + 1 < body.length &&
          _isDigit(body.codeUnitAt(i - 1)) &&
          _isDigit(body.codeUnitAt(i + 1));
      final isRupeeAbbreviation =
          i >= 2 && body.substring(i - 2, i).toLowerCase() == 'rs';
      if (!isDecimal && !isRupeeAbbreviation) {
        clauses.add(body.substring(start, i));
        start = i + 1;
      }
    }
    clauses.add(body.substring(start));
    return clauses;
  }

  bool _isDigit(int codeUnit) => codeUnit >= 48 && codeUnit <= 57;

  bool _hasStrongPaymentContext(
    String body, {
    required bool credit,
    bool allowPurchaseOf = false,
  }) {
    final hasAmount = RegExp(
      r'(?:\binr\b|\brs\.?|₹)\s*[\d,]+(?:\.\d{1,2})?',
      caseSensitive: false,
    ).hasMatch(body);
    if (!hasAmount) return false;

    final accountMovement = credit
        ? RegExp(
            r'\b(?:credited|received|deposited)\b.{0,60}\b(?:to|into)\s+(?:your\s+)?(?:a/c|account|card)\b|\badded\s+to\s+(?:your\s+)?(?:a/c|account|card)\b',
            caseSensitive: false,
          )
        : RegExp(
            r'\b(?:debited|withdrawn|transferred|sent)\b.{0,60}\bfrom\s+(?:your\s+)?(?:a/c|account|card)\b|\bcharged\b.{0,60}\b(?:on|to)\s+(?:your\s+)?(?:a/c|account|card)\b',
            caseSensitive: false,
          );
    if (accountMovement.hasMatch(body)) return true;
    if (credit) return false;

    // Older banks often put the purchase verb before the amount, unlike the
    // account-led template style. Accept those only when the amount is tied to
    // a concrete merchant/payee, so reward copy such as "Rs 100 spent via UPI"
    // cannot masquerade as a settled purchase. A bare "purchase of ... for
    // Rs ..." is ambiguous ad copy and is accepted only beside balance context,
    // never as the reason to override a promotional cue.
    final spentOrPaid = RegExp(
      r'\b(?:spent|paid)\b.{0,24}(?:\binr\b|\brs\.?|₹)\s*[\d,]+(?:\.\d{1,2})?\b.{0,32}\b(?:at|to)\s+[a-z0-9][a-z0-9*._& -]{1,36}\b',
      caseSensitive: false,
    );
    final purchaseOf = RegExp(
      r'\bpurchase\s+of\b.{1,60}\bfor\s+(?:\binr\b|\brs\.?|₹)\s*[\d,]+(?:\.\d{1,2})?\b',
      caseSensitive: false,
    );
    return spentOrPaid.hasMatch(body) ||
        (allowPurchaseOf && purchaseOf.hasMatch(body));
  }
}

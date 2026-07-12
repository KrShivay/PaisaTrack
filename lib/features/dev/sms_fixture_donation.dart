import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/raw_sms_repository.dart';

/// Copies an approved fixture payload out of the app.
typedef SmsFixtureCopier = Future<void> Function(String text);

/// Injectable boundary used only after the user approves the exact preview.
final smsFixtureCopierProvider = Provider<SmsFixtureCopier>(
  (ref) => (text) => Clipboard.setData(ClipboardData(text: text)),
);

/// Builds privacy-masked, device-provenance fixtures for voluntary donation.
class SmsFixtureDonation {
  const SmsFixtureDonation();

  static final _balance = RegExp(
    r'\b((?:available\s+)?bal(?:ance)?\.?\s*(?:is|:)?\s*)'
    r'(?:inr|rs\.?|₹)?\s*[\d,]+(?:\.\d{1,2})?',
    caseSensitive: false,
  );
  static final _account = RegExp(
    r'\b((?:a/?c|acct|account|card)(?:\s+(?:no\.?|number|ending))?\s*'
    r'(?:is|:|x+|-)?\s*)[x*\d -]{4,}',
    caseSensitive: false,
  );
  static final _reference = RegExp(
    r'\b((?:ref(?:erence)?|utr|rrn)(?:\s+(?:no\.?|number))?\s*'
    r'(?:is|:)?\s*)[a-z0-9-]{6,}',
    caseSensitive: false,
  );
  // A Title-Case personal name: one to three capitalized words (e.g. "Rahul",
  // "Rahul Kumar", "Priya S Sharma"). Deliberately case-sensitive so ALLCAPS
  // merchant/bank tokens ("AMAZON", "HDFC") and lowercase words are NOT treated
  // as names. `_fullName` additionally requires >=2 words, which keeps
  // single-token merchants after a transfer preposition from being masked.
  static const _name = r'[A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,2}';
  static const _fullName = r'[A-Z][a-z]+(?:\s+[A-Z][a-z]+){1,2}';

  // Title/greeting-anchored name, e.g. "Dear Rahul Kumar", "Ms. Anjali", and a
  // trailing "Dear Rahul" at end-of-string (the Title-Case bound stops the
  // match at the first lowercase word, so it never swallows the sentence).
  static final _greetingName = RegExp(
    r'\b(Dear|DEAR|Mr\.?|MR\.?|Mrs\.?|MRS\.?|Ms\.?|MS\.?|Miss|MISS|Name\s*:?)\s+'
    '($_name)',
  );
  // Untitled leading name before a transaction verb, e.g.
  // "Rahul Kumar paid Rs 500 ...".
  static final _leadingName = RegExp(
    '^($_fullName)\\s+'
    r'([Pp]aid|[Ss]ent|[Tt]ransferred|[Ss]pent|[Rr]eceived|[Ww]ithdrew)\b',
  );
  // Payee/counterparty name after a transfer preposition, e.g. "paid to Priya
  // Sharma", "sent to John Doe", "received from Priya Sharma". Requires a full
  // (>=2 word) name so "to AMAZON" / "at Swiggy" are left intact.
  static final _payeeName = RegExp(
    r'\b([Pp]aid to|[Ss]ent to|[Tt]ransferred to|[Rr]eceived from|[Tt]o|[Ff]rom|[Ff]or)\s+'
    '($_fullName)',
  );
  // UPI VPA / email handle: mask the local-part (which can carry a personal
  // name or phone number) and keep the non-personal PSP/domain, e.g.
  // "rahul.kumar@paytm" -> "<VPA>@paytm", "swiggy@okhdfc" -> "<VPA>@okhdfc".
  static final _handle = RegExp(
    r'\b[a-z0-9][a-z0-9._%+-]*@([a-z0-9][a-z0-9.-]*[a-z0-9])',
    caseSensitive: false,
  );
  // >=6 consecutive digits (account/reference runs) -> <ACCOUNT>, but NOT when
  // the run is a currency-adjacent transaction amount (e.g. "Rs 250000"), which
  // must survive per T-082.
  static final _longDigits = RegExp(
    r'(?<![\d.,])(?<!(?:inr|rs\.?|₹)\s{0,4})\d{6,}(?![\d.,])',
    caseSensitive: false,
  );

  /// Masks personal names (titled, untitled-leading, and payee/counterparty),
  /// UPI/email handles, account/reference identifiers, and balances while
  /// retaining transaction amounts and the surrounding message structure.
  String sanitize(String body) {
    return body
        .replaceAllMapped(_balance, (match) => '${match[1]}<BALANCE>')
        .replaceAllMapped(_account, (match) => '${match[1]}<ACCOUNT>')
        .replaceAllMapped(_reference, (match) => '${match[1]}<ACCOUNT>')
        .replaceAllMapped(_handle, (match) => '<VPA>@${match[1]}')
        .replaceAllMapped(_greetingName, (match) => '${match[1]} <NAME>')
        .replaceAllMapped(_leadingName, (match) => '<NAME> ${match[2]}')
        .replaceAllMapped(_payeeName, (match) => '${match[1]} <NAME>')
        .replaceAll(_longDigits, '<ACCOUNT>');
  }

  /// Returns the exact text shown in the approval preview and later copied.
  String fixture(UnparsedSms sms) {
    return const JsonEncoder.withIndent('  ').convert({
      'sender': sms.sender,
      'body': sanitize(sms.body),
      'provenance': 'device',
    });
  }
}

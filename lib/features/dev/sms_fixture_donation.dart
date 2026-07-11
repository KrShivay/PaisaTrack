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
  static final _namedPerson = RegExp(
    r'\b(dear|mr\.?|mrs\.?|ms\.?|miss|name\s*:?)\s+'
    r'([a-z][a-z .]{1,40}?)(?=,|\.|\s+(?:your|a/?c|account|has|was)\b)',
    caseSensitive: false,
  );
  static final _longDigits = RegExp(r'(?<![\d.,])\d{6,}(?![\d.,])');

  /// Masks personal names, account/reference identifiers, and balances while
  /// retaining transaction amounts and the surrounding message structure.
  String sanitize(String body) {
    return body
        .replaceAllMapped(_balance, (match) => '${match[1]}<BALANCE>')
        .replaceAllMapped(_account, (match) => '${match[1]}<ACCOUNT>')
        .replaceAllMapped(_reference, (match) => '${match[1]}<ACCOUNT>')
        .replaceAllMapped(
          _namedPerson,
          (match) => '${match[1]} <NAME>',
        )
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

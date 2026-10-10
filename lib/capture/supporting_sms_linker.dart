import 'package:drift/drift.dart';

import '../data/db/database.dart';
import '../data/models/source_currency.dart';
import '../data/repositories/expected_event_repository.dart';
import '../data/repositories/transaction_sms_repository.dart';
import 'supporting_sms_classifier.dart';

/// Links supporting SMS (dividend advice, RD instalment notice, EMI notice,
/// UPI collect request) to the transaction they describe (ADR 0032).
///
/// Linking is deterministic and conservative. A link needs all of:
///
/// * exact amount in integer paise and the same source-currency bucket;
/// * a time window: notices and requests up to 7 days before the transaction
///   (plus 3 days after, for "debited" confirmations), dividend and RD
///   advices within 3 days either side;
/// * the transaction direction the kind implies, a settled, live, canonical
///   (non-duplicate, non-deleted) row;
/// * at least one corroborator: account suffix, reference equality,
///   counterparty VPA or name, or (dividends) a company-name token that also
///   appears in the bank narration;
/// * exactly one candidate transaction — otherwise the linker abstains.
///
/// It only writes `sms_transaction_links`; it never creates, changes or
/// deletes a transaction. Every query is bounded by an indexed timestamp
/// window or a row limit. Works in both arrival orders: [linkMessage] when
/// the supporting SMS arrives after the transaction, [linkTransaction] when
/// the transaction arrives after the SMS.
class SupportingSmsLinker {
  SupportingSmsLinker(this._db, this._classifier)
      : _links = TransactionSmsRepository(_db);

  final AppDatabase _db;
  final SupportingSmsClassifier _classifier;
  final TransactionSmsRepository _links;

  /// How far before the transaction a notice or request may arrive.
  static const noticeLead = Duration(days: 7);

  /// How long after the transaction a notice or request may still arrive.
  static const noticeGrace = Duration(days: 3);

  /// Window either side of the transaction for dividend and RD advices.
  static const adviceWindow = Duration(days: 3);

  /// Maximum raw SMS inspected per transaction.
  static const lookbackRowLimit = 200;

  /// Maximum raw SMS inspected by one [backfill] pass.
  static const backfillRowLimit = 500;

  static bool _isNotice(SupportingSmsKind kind) =>
      kind == SupportingSmsKind.emiNotice ||
      kind == SupportingSmsKind.collectRequest;

  /// Links the stored raw SMS [smsId] to its transaction, if exactly one
  /// qualifies. Returns the number of links written (0 or 1).
  Future<int> linkMessage(String smsId) async {
    final sms = await (_db.select(_db.rawSms)
          ..where((row) => row.id.equals(smsId)))
        .getSingleOrNull();
    if (sms == null) return 0;
    if (await _isPrimaryOrDisposed(smsId)) return 0;
    if (await _links.hasLink(smsId)) return 0;
    final info = _classifier.classify(sms.body);
    if (info == null) return 0;
    final transaction = await _uniqueCandidate(sms, info);
    if (transaction == null) return 0;
    return await _write(sms, info, transaction) ? 1 : 0;
  }

  /// Looks back for unlinked supporting SMS that describe the stored
  /// transaction [transactionId]. Returns the number of links written.
  Future<int> linkTransaction(String transactionId) async {
    final transaction = await (_db.select(_db.transactions)
          ..where((row) => row.id.equals(transactionId)))
        .getSingleOrNull();
    if (transaction == null || !_isLinkTarget(transaction)) return 0;

    final at = DateTime.fromMillisecondsSinceEpoch(
      transaction.ts,
      isUtc: true,
    );
    final candidates = _unlinkedRawSms()
      ..where(
        (row) => row.receivedAt.isBetweenValues(
          at.subtract(noticeLead),
          at.add(adviceWindow),
        ),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.receivedAt)])
      ..limit(lookbackRowLimit);
    var written = 0;
    for (final sms in await candidates.get()) {
      final info = _classifier.classify(sms.body);
      if (info == null) continue;
      final unique = await _uniqueCandidate(sms, info);
      if (unique?.id != transaction.id) continue;
      if (await _write(sms, info, unique!)) written++;
    }
    return written;
  }

  /// One-shot, idempotent backfill over retained raw SMS: links unlinked
  /// supporting messages to existing transactions and records the origin SMS
  /// of already-fulfilled expected events. Bounded by [backfillRowLimit] raw
  /// rows per pass, newest first. Returns the number of links written.
  Future<int> backfill() async {
    final candidates = _unlinkedRawSms()
      ..orderBy([(row) => OrderingTerm.desc(row.receivedAt)])
      ..limit(backfillRowLimit);
    var written = 0;
    for (final sms in await candidates.get()) {
      final info = _classifier.classify(sms.body);
      if (info == null) continue;
      final transaction = await _uniqueCandidate(sms, info);
      if (transaction == null) continue;
      if (await _write(sms, info, transaction)) written++;
    }
    written += await ExpectedEventRepository(
      _db,
      supportingClassifier: _classifier,
    ).linkFulfilledOriginSms(limit: backfillRowLimit);
    return written;
  }

  /// Raw SMS that are neither a transaction's primary source, a disposition,
  /// nor already linked.
  SimpleSelectStatement<$RawSmsTable, RawSm> _unlinkedRawSms() {
    final primaryIds = _db.selectOnly(_db.transactions)
      ..addColumns([_db.transactions.smsId])
      ..where(_db.transactions.smsId.isNotNull());
    final dispositionIds = _db.selectOnly(_db.smsDispositions)
      ..addColumns([_db.smsDispositions.smsId]);
    final linkedIds = _db.selectOnly(_db.smsTransactionLinks)
      ..addColumns([_db.smsTransactionLinks.smsId]);
    return _db.select(_db.rawSms)
      ..where(
        (row) =>
            row.id.isNotInQuery(primaryIds) &
            row.id.isNotInQuery(dispositionIds) &
            row.id.isNotInQuery(linkedIds),
      );
  }

  Future<bool> _isPrimaryOrDisposed(String smsId) async {
    final primary = await (_db.selectOnly(_db.transactions)
          ..addColumns([_db.transactions.id])
          ..where(_db.transactions.smsId.equals(smsId))
          ..limit(1))
        .getSingleOrNull();
    if (primary != null) return true;
    final disposition = await (_db.selectOnly(_db.smsDispositions)
          ..addColumns([_db.smsDispositions.smsId])
          ..where(_db.smsDispositions.smsId.equals(smsId))
          ..limit(1))
        .getSingleOrNull();
    return disposition != null;
  }

  static bool _isLinkTarget(Transaction transaction) =>
      transaction.lifecycleState == 'settled' &&
      !transaction.isDeleted &&
      !transaction.isNotTransaction &&
      transaction.duplicateOfTxnId == null;

  Future<bool> _write(
    RawSm sms,
    SupportingSmsInfo info,
    Transaction transaction,
  ) {
    final evidence = _corroborators(info, transaction);
    return _links.recordLink(
      smsId: sms.id,
      transactionId: transaction.id,
      kind: info.kind.wireName,
      basis: ['amount', 'window', ...evidence].join('+'),
    );
  }

  /// The single live transaction [info] describes, or null when none or more
  /// than one qualifies.
  Future<Transaction?> _uniqueCandidate(
    RawSm sms,
    SupportingSmsInfo info,
  ) async {
    final received = sms.receivedAt.toUtc();
    final (from, to) = _isNotice(info.kind)
        ? (received.subtract(noticeGrace), received.add(noticeLead))
        : (
            received.subtract(adviceWindow),
            received.add(adviceWindow),
          );
    // The SQL amount range only narrows the scan (REAL column); equality is
    // decided on integer paise below.
    final low = (info.amountPaise - 1) / 100;
    final high = (info.amountPaise + 1) / 100;
    final rows = await (_db.select(_db.transactions)
          ..where(
            (row) =>
                row.ts.isBetweenValues(
                  from.millisecondsSinceEpoch,
                  to.millisecondsSinceEpoch,
                ) &
                row.direction.equals(info.kind.transactionDirection) &
                row.lifecycleState.equals('settled') &
                row.isDeleted.equals(false) &
                row.isNotTransaction.equals(false) &
                row.duplicateOfTxnId.isNull() &
                row.amount.isBetweenValues(low, high),
          ))
        .get();

    final qualifying = rows.where((transaction) {
      if ((transaction.amount * 100).round() != info.amountPaise) return false;
      final currency = SourceCurrency(
        code: transaction.currencyCode,
        symbol: transaction.currencySymbol,
      );
      if (!info.currency.sameBucket(currency)) return false;
      if (!_dueDateAgrees(info, transaction)) return false;
      return _corroborators(info, transaction).isNotEmpty;
    }).toList(growable: false);
    return qualifying.length == 1 ? qualifying.single : null;
  }

  /// A stated due date vetoes a transaction that is far from it.
  static bool _dueDateAgrees(SupportingSmsInfo info, Transaction transaction) {
    final due = info.dueDate;
    if (due == null || !_isNotice(info.kind)) return true;
    final at = DateTime.fromMillisecondsSinceEpoch(
      transaction.ts,
      isUtc: true,
    );
    return at.difference(due).abs() <= const Duration(days: 5);
  }

  /// Names the corroborating evidence shared by [info] and [transaction];
  /// empty when there is none.
  static List<String> _corroborators(
    SupportingSmsInfo info,
    Transaction transaction,
  ) {
    final evidence = <String>[];
    if (_accountMatches(info.accountSuffixes, transaction.accountHint)) {
      evidence.add('account_suffix');
    }
    final reference = transaction.refId?.trim().toUpperCase();
    if (reference != null &&
        reference.isNotEmpty &&
        reference == info.reference) {
      evidence.add('reference');
    }
    final vpa = transaction.counterpartyVpa?.trim().toLowerCase();
    final requester = SupportingSmsClassifier.significantTokens(
      info.counterpartyName,
    );
    final narration = SupportingSmsClassifier.significantTokens(
      '${transaction.merchantRaw ?? ''} ${vpa ?? ''}',
    );
    if ((vpa != null && vpa.isNotEmpty && vpa == info.counterpartyVpa) ||
        requester.any(narration.contains)) {
      evidence.add('counterparty');
    }
    if (info.kind == SupportingSmsKind.dividend &&
        info.bodyTokens.any(
          SupportingSmsClassifier.significantTokens(transaction.merchantRaw)
              .contains,
        )) {
      evidence.add('company_token');
    }
    return evidence;
  }

  static bool _accountMatches(Set<String> suffixes, String? accountHint) {
    if (suffixes.isEmpty || accountHint == null) return false;
    final runs = RegExp(r'\d{3,}').allMatches(accountHint);
    if (runs.isEmpty) return false;
    final hint = runs.last.group(0)!;
    return suffixes.any(
      (suffix) => hint.endsWith(suffix) || suffix.endsWith(hint),
    );
  }
}

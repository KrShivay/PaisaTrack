import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../db/database_provider.dart';

const cardSourceAuditCandidatePageSize = 40;
const _cardSourceAuditConflictLimit = 20;
const _cardSourceAuditSourceLimit = 100;
const _cardSourceAuditBucketLimit = 20;
const _cardSourceAuditMaximumCandidatePageSize = 100;

/// Cursor for the deterministic, newest-first possible-card-transaction feed.
class CardSourceAuditCursor {
  const CardSourceAuditCursor({required this.timestampMs, required this.id});

  final int timestampMs;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is CardSourceAuditCursor &&
      timestampMs == other.timestampMs &&
      id == other.id;

  @override
  int get hashCode => Object.hash(timestampMs, id);
}

class CardSourceAuditBucket {
  const CardSourceAuditBucket({
    required this.lifecycleState,
    required this.currencyCode,
    required this.currencySymbol,
    required this.rowCount,
  });

  final String lifecycleState;
  final String? currencyCode;
  final String? currencySymbol;
  final int rowCount;

  String get currencyLabel => _currencyLabel(currencyCode, currencySymbol);
}

class CardSourceAuditSource {
  const CardSourceAuditSource({
    required this.kind,
    required this.maskedIdentifier,
    required this.nickname,
    required this.institution,
    required this.rowCount,
    required this.buckets,
    required this.totalBucketCount,
  });

  final String kind;
  final String maskedIdentifier;
  final String nickname;
  final String institution;
  final int rowCount;
  final List<CardSourceAuditBucket> buckets;
  final int totalBucketCount;

  bool get bucketsTruncated => buckets.length < totalBucketCount;
}

class CardSourceAuditCandidate {
  const CardSourceAuditCandidate({
    required this.id,
    required this.timestampMs,
    required this.amount,
    required this.direction,
    required this.currencyCode,
    required this.currencySymbol,
    required this.lifecycleState,
    required this.status,
    required this.sourceKind,
    required this.maskedIdentifier,
    required this.nickname,
    required this.institution,
    required this.sourceAvailable,
    required this.isDeleted,
    required this.isNotTransaction,
    required this.isDuplicate,
    required this.isAnalyticsExcluded,
    required this.ownedTransferId,
  });

  /// Kept for paging only; never rendered in the audit UI.
  final String id;
  final int timestampMs;
  final double amount;
  final String direction;
  final String? currencyCode;
  final String? currencySymbol;
  final String lifecycleState;
  final String status;
  final String sourceKind;
  final String maskedIdentifier;
  final String nickname;
  final String institution;
  final bool sourceAvailable;
  final bool isDeleted;
  final bool isNotTransaction;
  final bool isDuplicate;
  final bool isAnalyticsExcluded;
  final String? ownedTransferId;

  String get currencyLabel => _currencyLabel(currencyCode, currencySymbol);
}

class CardSourceAuditConflict {
  const CardSourceAuditConflict({
    required this.channel,
    required this.maskedIdentifier,
    required this.sourceIdCount,
    required this.institutionLabelCount,
    required this.hasUnlinkedRows,
  });

  final String channel;
  final String maskedIdentifier;
  final int sourceIdCount;
  final int institutionLabelCount;
  final bool hasUnlinkedRows;
}

class CardSourceAuditReport {
  const CardSourceAuditReport({
    required this.sources,
    required this.sourcesTruncated,
    required this.conflicts,
    required this.conflictsTruncated,
    required this.candidates,
    required this.nextCursor,
    required this.candidatesTruncated,
  });

  final List<CardSourceAuditSource> sources;
  final bool sourcesTruncated;
  final List<CardSourceAuditConflict> conflicts;
  final bool conflictsTruncated;
  final List<CardSourceAuditCandidate> candidates;
  final CardSourceAuditCursor? nextCursor;
  final bool candidatesTruncated;
}

/// Read-only report over already stored source and transaction provenance.
///
/// Queries aggregate whole-history source facts in SQLite and only materialize
/// one bounded page of possible card transactions. No SMS, source writes,
/// transfer reconciliation, relationship changes or accounting projections
/// are read or performed here.
class CardSourceAuditRepository {
  CardSourceAuditRepository(
    this._database, {
    int pageSize = cardSourceAuditCandidatePageSize,
  }) : pageSize = _validatedPageSize(pageSize);

  final AppDatabase _database;
  final int pageSize;

  Future<CardSourceAuditReport> load({CardSourceAuditCursor? cursor}) async {
    return _database.transaction(() async {
      final sources = await _loadSources();
      final conflicts = await _loadConflicts();
      final candidates = await _loadCandidates(cursor);
      return CardSourceAuditReport(
        sources: sources.items,
        sourcesTruncated: sources.truncated,
        conflicts: conflicts.items,
        conflictsTruncated: conflicts.truncated,
        candidates: candidates.items,
        nextCursor: candidates.nextCursor,
        candidatesTruncated: candidates.truncated,
      );
    });
  }

  Future<_SourceResult> _loadSources() async {
    final rows = await _database.customSelect(
      '''
WITH source_page AS (
  SELECT id, kind, masked_identifier, nickname, institution
  FROM payment_sources
  ORDER BY lower(kind), lower(masked_identifier), id
  LIMIT ?
), bucket_aggregates AS (
  SELECT p.id AS source_id, p.kind AS source_kind,
    p.masked_identifier AS masked_identifier, p.nickname AS nickname,
    p.institution AS institution,
    t.lifecycle_state AS lifecycle_state, t.currency_code AS currency_code,
    t.currency_symbol AS currency_symbol, COUNT(t.id) AS bucket_row_count
  FROM source_page p
  LEFT JOIN transactions t ON t.payment_source_id = p.id
  GROUP BY p.id, p.kind, p.masked_identifier, p.nickname, p.institution,
    t.lifecycle_state, t.currency_code, t.currency_symbol
), bucket_ranked AS (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY source_id
      ORDER BY lifecycle_state, currency_code, currency_symbol
    ) AS bucket_number,
    COUNT(*) OVER (PARTITION BY source_id) AS total_bucket_count,
    SUM(bucket_row_count) OVER (PARTITION BY source_id) AS total_row_count
  FROM bucket_aggregates
)
SELECT * FROM bucket_ranked WHERE bucket_number <= ?
ORDER BY lower(source_kind), lower(masked_identifier), source_id,
  lifecycle_state, currency_code, currency_symbol
''',
      variables: [
        Variable.withInt(_cardSourceAuditSourceLimit + 1),
        Variable.withInt(_cardSourceAuditBucketLimit),
      ],
    ).get();

    final byId = <String, _SourceBuilder>{};
    for (final row in rows) {
      final id = row.read<String>('source_id');
      final builder = byId.putIfAbsent(
        id,
        () => _SourceBuilder(
          kind: _storedLabel(row.read<String>('source_kind')),
          maskedIdentifier: maskStoredHint(
            row.read<String>('masked_identifier'),
          ),
          nickname: _storedLabelOrUnavailable(
            row.readNullable<String>('nickname'),
          ),
          institution: _storedLabelOrUnavailable(
            row.readNullable<String>('institution'),
          ),
          totalRowCount: row.read<int>('total_row_count'),
          totalBucketCount: row.read<int>('total_bucket_count'),
        ),
      );
      final count = row.read<int>('bucket_row_count');
      if (count == 0) continue;
      final lifecycle = row.readNullable<String>('lifecycle_state');
      final code = row.readNullable<String>('currency_code');
      final symbol = row.readNullable<String>('currency_symbol');
      builder.buckets.add(
        CardSourceAuditBucket(
          lifecycleState: _storedLabelOrUnavailable(lifecycle),
          currencyCode: code,
          currencySymbol: symbol,
          rowCount: count,
        ),
      );
    }

    final builders = byId.values.toList(growable: false);
    final truncated = builders.length > _cardSourceAuditSourceLimit;
    final visible = truncated
        ? builders.take(_cardSourceAuditSourceLimit).toList(growable: false)
        : builders;
    return _SourceResult(
      visible.map((builder) => builder.build()).toList(growable: false),
      truncated,
    );
  }

  Future<_ConflictResult> _loadConflicts() async {
    // Keep this expression identical to the legacy source-key construction:
    // trim, remove spaces/dashes, map '*' to 'x', lowercase, then append the
    // lowercased channel. The key is used only inside SQL and is never returned.
    const normalizedHint =
        "lower(replace(replace(replace(trim(t.account_hint), ' ', ''), '*', 'x'), '-', ''))";
    const normalizedChannel = 'lower(t.channel)';
    final rows = await _database.customSelect(
      '''
WITH identity_evidence AS (
  SELECT $normalizedHint AS normalized_hint,
    $normalizedChannel AS normalized_channel,
    t.payment_source_id AS payment_source_id,
    NULLIF(trim(ps.institution), '') AS institution,
    t.payment_source_id IS NULL AS has_unlinked_row
  FROM transactions t
  LEFT JOIN payment_sources ps ON ps.id = t.payment_source_id
  WHERE t.account_hint IS NOT NULL AND trim(t.account_hint) <> ''
)
SELECT normalized_hint, normalized_channel,
  COUNT(DISTINCT payment_source_id) AS source_id_count,
  COUNT(DISTINCT institution) AS institution_label_count,
  MAX(has_unlinked_row) AS has_unlinked_rows
FROM identity_evidence
GROUP BY normalized_hint, normalized_channel
HAVING COUNT(DISTINCT payment_source_id) > 1
    OR COUNT(DISTINCT institution) > 1
ORDER BY normalized_channel, normalized_hint
LIMIT ?
''',
      variables: [Variable.withInt(_cardSourceAuditConflictLimit + 1)],
    ).get();
    final truncated = rows.length > _cardSourceAuditConflictLimit;
    final visible = truncated ? rows.take(_cardSourceAuditConflictLimit) : rows;
    return _ConflictResult(
      visible
          .map(
            (row) => CardSourceAuditConflict(
              channel: _storedLabel(row.read<String>('normalized_channel')),
              maskedIdentifier: maskStoredHint(
                row.read<String>('normalized_hint'),
              ),
              sourceIdCount: row.read<int>('source_id_count'),
              institutionLabelCount: row.read<int>('institution_label_count'),
              hasUnlinkedRows: row.read<int>('has_unlinked_rows') != 0,
            ),
          )
          .toList(growable: false),
      truncated,
    );
  }

  Future<_CandidateResult> _loadCandidates(
    CardSourceAuditCursor? cursor,
  ) async {
    final variables = <Variable<Object>>[];
    final cursorClause =
        cursor == null ? '' : '''AND (t.ts < ? OR (t.ts = ? AND t.id < ?))''';
    if (cursor != null) {
      variables
        ..add(Variable.withInt(cursor.timestampMs))
        ..add(Variable.withInt(cursor.timestampMs))
        ..add(Variable.withString(cursor.id));
    }
    variables.add(Variable.withInt(pageSize + 1));
    final rows = await _database.customSelect(
      '''
SELECT t.id AS transaction_id, t.ts AS timestamp_ms, t.amount AS amount,
  t.direction AS direction, t.currency_code AS currency_code,
  t.currency_symbol AS currency_symbol, t.lifecycle_state AS lifecycle_state,
  t.status AS status, t.is_deleted AS is_deleted,
  t.is_not_transaction AS is_not_transaction,
  t.duplicate_of_txn_id AS duplicate_of_txn_id,
  t.is_analytics_excluded AS is_analytics_excluded,
  t.owned_transfer_id AS owned_transfer_id,
  t.account_hint AS account_hint, ps.id AS stored_source_id,
  ps.kind AS source_kind, ps.masked_identifier AS masked_identifier,
  ps.nickname AS nickname, ps.institution AS institution
FROM transactions t
LEFT JOIN payment_sources ps ON ps.id = t.payment_source_id
WHERE lower(t.channel) = 'card'
$cursorClause
ORDER BY t.ts DESC, t.id DESC
LIMIT ?
''',
      variables: variables,
    ).get();

    final truncated = rows.length > pageSize;
    final visibleRows = truncated ? rows.take(pageSize).toList() : rows;
    final items = visibleRows
        .map(
          (row) => CardSourceAuditCandidate(
            id: row.read<String>('transaction_id'),
            timestampMs: row.read<int>('timestamp_ms'),
            amount: row.read<double>('amount'),
            direction: _storedLabel(row.read<String>('direction')),
            currencyCode: row.readNullable<String>('currency_code'),
            currencySymbol: row.readNullable<String>('currency_symbol'),
            lifecycleState: _storedLabelOrUnavailable(
              row.readNullable<String>('lifecycle_state'),
            ),
            status: _storedLabelOrUnavailable(
              row.readNullable<String>('status'),
            ),
            sourceKind: _storedLabelOrUnavailable(
              row.readNullable<String>('source_kind'),
            ),
            maskedIdentifier: maskStoredHint(
              row.readNullable<String>('masked_identifier') ??
                  row.readNullable<String>('account_hint'),
            ),
            nickname: _storedLabelOrUnavailable(
              row.readNullable<String>('nickname'),
            ),
            institution: _storedLabelOrUnavailable(
              row.readNullable<String>('institution'),
            ),
            sourceAvailable:
                row.readNullable<String>('stored_source_id') != null,
            isDeleted: row.read<int>('is_deleted') != 0,
            isNotTransaction: row.read<int>('is_not_transaction') != 0,
            isDuplicate:
                row.readNullable<String>('duplicate_of_txn_id') != null,
            isAnalyticsExcluded: row.read<int>('is_analytics_excluded') != 0,
            ownedTransferId: row.readNullable<String>('owned_transfer_id'),
          ),
        )
        .toList(growable: false);
    final last = truncated && items.isNotEmpty ? items.last : null;
    return _CandidateResult(
      items,
      truncated && last != null
          ? CardSourceAuditCursor(
              timestampMs: last.timestampMs,
              id: last.id,
            )
          : null,
      truncated,
    );
  }
}

String maskStoredHint(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return 'Not available';
  final numericOnly = RegExp(r'^\d+$').hasMatch(trimmed);
  final maskedSuffix = RegExp(r'^[xX*#•\s-]*\d{4}$').hasMatch(trimmed);
  if (!numericOnly && !maskedSuffix) return 'Not available';
  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 4) return 'Not available';
  return '••••${digits.substring(digits.length - 4)}';
}

String _storedLabel(String value) {
  final clean = value.trim();
  return clean.isEmpty ? 'Not available' : clean;
}

String _storedLabelOrUnavailable(String? value) {
  final clean = value?.trim();
  return clean == null || clean.isEmpty ? 'Not recorded' : clean;
}

String _currencyLabel(String? code, String? symbol) {
  final codeLabel = code == null
      ? 'Code unavailable'
      : code.isEmpty
          ? 'Blank code'
          : code.trim().isEmpty
              ? 'Whitespace-only code'
              : code;
  final symbolLabel = symbol == null
      ? 'symbol unavailable'
      : symbol.isEmpty
          ? 'blank symbol'
          : symbol.trim().isEmpty
              ? 'whitespace-only symbol'
              : symbol;
  if (code == null && symbol == null) return 'Currency unavailable';
  if (code != null && symbol != null) return '$codeLabel · $symbolLabel';
  if (code != null) return '$codeLabel · $symbolLabel';
  if (symbol != null) return '$symbolLabel · code unavailable';
  return 'Currency unavailable';
}

int _validatedPageSize(int value) {
  if (value < 1 || value > _cardSourceAuditMaximumCandidatePageSize) {
    throw ArgumentError.value(
      value,
      'pageSize',
      'Must be between 1 and $_cardSourceAuditMaximumCandidatePageSize',
    );
  }
  return value;
}

class _SourceBuilder {
  _SourceBuilder({
    required this.kind,
    required this.maskedIdentifier,
    required this.nickname,
    required this.institution,
    required this.totalRowCount,
    required this.totalBucketCount,
  });

  final String kind;
  final String maskedIdentifier;
  final String nickname;
  final String institution;
  final int totalRowCount;
  final int totalBucketCount;
  final buckets = <CardSourceAuditBucket>[];

  CardSourceAuditSource build() => CardSourceAuditSource(
        kind: kind,
        maskedIdentifier: maskedIdentifier,
        nickname: nickname,
        institution: institution,
        rowCount: totalRowCount,
        buckets: List.unmodifiable(buckets),
        totalBucketCount: totalRowCount == 0 ? 0 : totalBucketCount,
      );
}

class _SourceResult {
  const _SourceResult(this.items, this.truncated);

  final List<CardSourceAuditSource> items;
  final bool truncated;
}

class _ConflictResult {
  const _ConflictResult(this.items, this.truncated);

  final List<CardSourceAuditConflict> items;
  final bool truncated;
}

class _CandidateResult {
  const _CandidateResult(this.items, this.nextCursor, this.truncated);

  final List<CardSourceAuditCandidate> items;
  final CardSourceAuditCursor? nextCursor;
  final bool truncated;
}

final cardSourceAuditRepositoryProvider =
    FutureProvider<CardSourceAuditRepository>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  return CardSourceAuditRepository(database);
});

final cardSourceAuditReportProvider = FutureProvider.autoDispose
    .family<CardSourceAuditReport, CardSourceAuditCursor?>(
  (ref, cursor) async {
    final repository =
        await ref.watch(cardSourceAuditRepositoryProvider.future);
    return repository.load(cursor: cursor);
  },
);

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../enrichment/merchant_clusterer.dart';
import '../../enrichment/merchant_resolver.dart';
import '../db/database.dart';
import '../db/database_provider.dart';

class PayeeIdentity {
  const PayeeIdentity({
    required this.key,
    required this.displayName,
    required this.aliases,
    required this.transactionCount,
    this.merchantId,
    this.userLabel,
  });

  final String key;
  final String displayName;
  final List<String> aliases;
  final int transactionCount;
  final String? merchantId;
  final String? userLabel;
}

class PayeeIdentityCursor {
  const PayeeIdentityCursor({
    required this.displayName,
    required this.identityKey,
  });

  final String displayName;
  final String identityKey;

  @override
  bool operator ==(Object other) =>
      other is PayeeIdentityCursor &&
      other.displayName == displayName &&
      other.identityKey == identityKey;

  @override
  int get hashCode => Object.hash(displayName, identityKey);
}

class PayeeIdentityQuery {
  const PayeeIdentityQuery({
    this.search = '',
    this.unlabeledOnly = false,
    this.after,
    this.limit = 50,
  }) : assert(limit > 0);

  final String search;
  final bool unlabeledOnly;
  final PayeeIdentityCursor? after;
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is PayeeIdentityQuery &&
      other.search == search &&
      other.unlabeledOnly == unlabeledOnly &&
      other.after == after &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(search, unlabeledOnly, after, limit);
}

class PayeeIdentityPage {
  const PayeeIdentityPage({
    required this.items,
    required this.hasMore,
  });

  final List<PayeeIdentity> items;
  final bool hasMore;

  PayeeIdentityCursor? get nextCursor => hasMore && items.isNotEmpty
      ? PayeeIdentityCursor(
          displayName: items.last.displayName,
          identityKey: items.last.key,
        )
      : null;
}

class PayeeLabelPreview {
  const PayeeLabelPreview({
    required this.affectedTransactionCount,
    required this.conflictingAliases,
  });

  final int affectedTransactionCount;
  final List<String> conflictingAliases;

  bool get hasConflicts => conflictingAliases.isNotEmpty;
}

class PayeeAliasConflict implements Exception {
  const PayeeAliasConflict(this.aliases);

  final List<String> aliases;

  @override
  String toString() => 'Aliases already belong to another payee: '
      '${aliases.join(', ')}';
}

class PayeeLabelRepository {
  const PayeeLabelRepository(this._database);

  final AppDatabase _database;

  Stream<List<PayeeIdentity>> watchIdentities() =>
      watchPage(const PayeeIdentityQuery()).map((page) => page.items);

  Stream<PayeeIdentityPage> watchPage(PayeeIdentityQuery query) =>
      _identityRows(query).watch().asyncMap(_decodePage);

  Future<PayeeIdentityPage> loadPage(PayeeIdentityQuery query) async =>
      _decodePage(await _identityRows(query).get());

  Future<List<MerchantClusterSuggestion>> duplicateSuggestions() =>
      MerchantClusterer(_database).cluster();

  Future<PayeeIdentityPage> _decodePage(List<QueryRow> rows) async {
    if (rows.isEmpty) {
      return const PayeeIdentityPage(items: [], hasMore: false);
    }
    final pageLimit = rows.first.read<int>('page_limit');
    final hasMore = rows.length > pageLimit;
    final visibleRows = rows.take(pageLimit).toList(growable: false);
    final keys = visibleRows.map((row) => row.read<String>('identity_key'));
    final aliases = await _loadAliases(keys);
    return PayeeIdentityPage(
      items: [
        for (final row in visibleRows)
          PayeeIdentity(
            key: row.read<String>('identity_key'),
            displayName: row.read<String>('display_name'),
            userLabel: row.readNullable<String>('user_label'),
            merchantId: row.readNullable<String>('merchant_id'),
            aliases: aliases[row.read<String>('identity_key')] ?? const [],
            transactionCount: row.read<int>('txn_count'),
          ),
      ],
      hasMore: hasMore,
    );
  }

  Selectable<QueryRow> _identityRows(PayeeIdentityQuery query) {
    final cursorClause = query.after == null
        ? ''
        : 'AND (display_name > ? OR '
            '(display_name = ? AND identity_key > ?))';
    final unlabeledClause = query.unlabeledOnly
        ? "AND (user_label IS NULL OR trim(user_label) = '')"
        : '';
    final variables = <Variable<Object>>[
      Variable.withString(query.search.trim().toLowerCase()),
      Variable.withInt(query.limit),
      if (query.after != null) ...[
        Variable.withString(query.after!.displayName),
        Variable.withString(query.after!.displayName),
        Variable.withString(query.after!.identityKey),
      ],
      Variable.withInt(query.limit + 1),
    ];
    return _database.customSelect(
      '''
WITH params AS (SELECT lower(?) AS search),
base AS (
  SELECT
    t.id,
    t.merchant_id,
    m.user_label,
    m.canonical_name,
    raw.normalized_key AS raw_key,
    raw.display_value AS raw_value,
    vpa.normalized_key AS vpa_key,
    vpa.display_value AS vpa_value
  FROM transactions AS t
  LEFT JOIN merchants AS m ON m.id = t.merchant_id
  LEFT JOIN payee_evidence AS raw
    ON raw.transaction_id = t.id AND raw.evidence_type = 'merchant_raw'
  LEFT JOIN payee_evidence AS vpa
    ON vpa.transaction_id = t.id AND vpa.evidence_type = 'counterparty_vpa'
  WHERE t.is_deleted = 0 AND t.duplicate_of_txn_id IS NULL
),
identity_rows AS (
  SELECT
    id,
    CASE
      WHEN merchant_id IS NOT NULL THEN 'merchant:' || merchant_id
      ELSE 'alias:' || COALESCE(raw_key, vpa_key)
    END AS identity_key,
    merchant_id,
    user_label,
    canonical_name,
    COALESCE(raw_value, vpa_value) AS first_alias
  FROM base
  WHERE merchant_id IS NOT NULL OR raw_key IS NOT NULL OR vpa_key IS NOT NULL
),
alias_rows AS (
  SELECT
    CASE
      WHEN merchant_id IS NOT NULL THEN 'merchant:' || merchant_id
      ELSE 'alias:' || COALESCE(raw_key, vpa_key)
    END AS identity_key,
    raw_value AS display_value
  FROM base
  WHERE raw_value IS NOT NULL
  UNION ALL
  SELECT
    CASE
      WHEN merchant_id IS NOT NULL THEN 'merchant:' || merchant_id
      ELSE 'alias:' || COALESCE(raw_key, vpa_key)
    END AS identity_key,
    vpa_value AS display_value
  FROM base
  WHERE vpa_value IS NOT NULL
),
identity_groups AS (
  SELECT
    identity_key,
    MAX(merchant_id) AS merchant_id,
    MAX(user_label) AS user_label,
    MAX(canonical_name) AS canonical_name,
    MIN(first_alias) AS first_alias,
    COUNT(*) AS txn_count
  FROM identity_rows
  GROUP BY identity_key
),
named AS (
  SELECT
    identity_key,
    merchant_id,
    user_label,
    COALESCE(
      NULLIF(trim(user_label), ''),
      NULLIF(trim(canonical_name), ''),
      first_alias,
      'Unknown payee'
    ) AS display_name,
    txn_count
  FROM identity_groups
)
SELECT
  named.identity_key,
  named.merchant_id,
  named.user_label,
  named.display_name,
  named.txn_count,
  ? AS page_limit
FROM named
CROSS JOIN params
WHERE (
  params.search = ''
  OR lower(named.display_name) LIKE '%' || params.search || '%'
  OR EXISTS (
    SELECT 1 FROM alias_rows AS a
    WHERE a.identity_key = named.identity_key
      AND lower(a.display_value) LIKE '%' || params.search || '%'
  )
)
$unlabeledClause
$cursorClause
ORDER BY named.display_name COLLATE BINARY ASC, named.identity_key ASC
LIMIT ?
''',
      variables: variables,
      readsFrom: {
        _database.transactions,
        _database.merchants,
        _database.payeeEvidence,
      },
    );
  }

  Future<Map<String, List<String>>> _loadAliases(Iterable<String> keys) async {
    final identityKeys = keys.toList(growable: false);
    if (identityKeys.isEmpty) return const {};
    final placeholders = List.filled(identityKeys.length, '?').join(', ');
    final rows = await _database.customSelect(
      '''
WITH base AS (
  SELECT
    t.id,
    t.merchant_id,
    raw.normalized_key AS raw_key,
    raw.display_value AS raw_value,
    vpa.normalized_key AS vpa_key,
    vpa.display_value AS vpa_value
  FROM transactions AS t
  LEFT JOIN payee_evidence AS raw
    ON raw.transaction_id = t.id AND raw.evidence_type = 'merchant_raw'
  LEFT JOIN payee_evidence AS vpa
    ON vpa.transaction_id = t.id AND vpa.evidence_type = 'counterparty_vpa'
  WHERE t.is_deleted = 0 AND t.duplicate_of_txn_id IS NULL
),
aliases AS (
  SELECT
    CASE
      WHEN merchant_id IS NOT NULL THEN 'merchant:' || merchant_id
      ELSE 'alias:' || COALESCE(raw_key, vpa_key)
    END AS identity_key,
    raw_value AS display_value
  FROM base
  WHERE raw_value IS NOT NULL
  UNION ALL
  SELECT
    CASE
      WHEN merchant_id IS NOT NULL THEN 'merchant:' || merchant_id
      ELSE 'alias:' || COALESCE(raw_key, vpa_key)
    END AS identity_key,
    vpa_value AS display_value
  FROM base
  WHERE vpa_value IS NOT NULL
)
SELECT DISTINCT identity_key, display_value
FROM aliases
WHERE identity_key IN ($placeholders)
ORDER BY identity_key ASC, display_value COLLATE BINARY ASC
''',
      variables: [
        for (final key in identityKeys) Variable.withString(key),
      ],
      readsFrom: {
        _database.transactions,
        _database.payeeEvidence,
      },
    ).get();
    final result = <String, List<String>>{};
    for (final row in rows) {
      result.putIfAbsent(row.read<String>('identity_key'), () => []).add(
            row.read<String>('display_value'),
          );
    }
    return result;
  }

  Future<PayeeLabelPreview> preview({
    required Iterable<String> aliases,
    String? merchantId,
  }) async {
    final normalized = _normalizedAliases(aliases);
    final conflicts = await _conflictingAliases(normalized, merchantId);
    final affected = await _matchingTransactions(
      normalizedAliases: normalized.keys.toSet(),
      merchantId: merchantId,
    );
    return PayeeLabelPreview(
      affectedTransactionCount: affected.length,
      conflictingAliases: conflicts,
    );
  }

  Future<int> saveLabel({
    required String label,
    required Iterable<String> aliases,
    String? merchantId,
    DateTime Function() clock = DateTime.now,
  }) {
    final trimmedLabel = label.trim();
    if (trimmedLabel.isEmpty) {
      throw ArgumentError.value(label, 'label', 'must not be empty');
    }
    final normalized = _normalizedAliases(aliases);
    if (normalized.isEmpty && merchantId == null) {
      throw ArgumentError('At least one alias is required for a new payee.');
    }

    return _database.transaction(() async {
      final existingMappings = normalized.isEmpty
          ? const <MerchantAliase>[]
          : await (_database.select(_database.merchantAliases)
                ..where((row) => row.alias.isIn(normalized.keys)))
              .get();
      final mappedMerchantIds = existingMappings
          .map((row) => row.merchantId)
          .where((id) => id != merchantId)
          .toSet();
      if (mappedMerchantIds.length > (merchantId == null ? 1 : 0)) {
        final conflicts = existingMappings
            .where((row) => row.merchantId != merchantId)
            .map((row) => normalized[row.alias] ?? row.alias)
            .toSet()
            .toList(growable: false);
        throw PayeeAliasConflict(conflicts);
      }

      final targetId = merchantId ??
          (mappedMerchantIds.isEmpty
              ? 'merchant_user_${clock().toUtc().microsecondsSinceEpoch}'
              : mappedMerchantIds.single);
      final existingMerchant = await (_database.select(_database.merchants)
            ..where((row) => row.id.equals(targetId)))
          .getSingleOrNull();
      final now = clock().toUtc();
      if (existingMerchant == null) {
        await _database.into(_database.merchants).insert(
              MerchantsCompanion.insert(
                id: targetId,
                canonicalName: trimmedLabel,
                userLabel: Value(trimmedLabel),
                firstSeen: now,
                lastSeen: now,
              ),
            );
      } else {
        await (_database.update(_database.merchants)
              ..where((row) => row.id.equals(targetId)))
            .write(MerchantsCompanion(userLabel: Value(trimmedLabel)));
      }

      for (final entry in normalized.entries) {
        await _database.into(_database.merchantAliases).insertOnConflictUpdate(
              MerchantAliasesCompanion.insert(
                alias: entry.key,
                merchantId: targetId,
                source: 'user',
                confidence: 1,
              ),
            );
      }
      final matches = await _matchingTransactions(
        normalizedAliases: normalized.keys.toSet(),
        merchantId: merchantId,
      );
      if (matches.isNotEmpty) {
        await (_database.update(_database.transactions)
              ..where((row) => row.id.isIn(matches.map((row) => row.id))))
            .write(
          TransactionsCompanion(
            merchantId: Value(targetId),
            updatedAt: Value(now),
          ),
        );
      }
      return matches.length;
    });
  }

  Future<List<String>> _conflictingAliases(
    Map<String, String> normalized,
    String? merchantId,
  ) async {
    if (normalized.isEmpty) return const [];
    final mappings = await (_database.select(_database.merchantAliases)
          ..where((row) => row.alias.isIn(normalized.keys)))
        .get();
    final merchantIds = mappings.map((row) => row.merchantId).toSet();
    final hasConflict = merchantId == null
        ? merchantIds.length > 1
        : merchantIds.any((id) => id != merchantId);
    if (!hasConflict) return const [];
    return mappings
        .where((row) => merchantId == null || row.merchantId != merchantId)
        .map((row) => normalized[row.alias] ?? row.alias)
        .toSet()
        .toList(growable: false);
  }

  Future<List<Transaction>> _matchingTransactions({
    required Set<String> normalizedAliases,
    String? merchantId,
  }) async {
    final rows = await (_database.select(_database.transactions)
          ..where(
            (row) =>
                row.isDeleted.equals(false) & row.duplicateOfTxnId.isNull(),
          ))
        .get();
    return rows.where((row) {
      if (merchantId != null && row.merchantId == merchantId) return true;
      return [row.merchantRaw, row.counterpartyVpa]
          .whereType<String>()
          .map(MerchantResolver.normalizeAlias)
          .any(normalizedAliases.contains);
    }).toList(growable: false);
  }

  static Map<String, String> _normalizedAliases(Iterable<String> aliases) {
    final result = <String, String>{};
    for (final alias in aliases) {
      final trimmed = alias.trim();
      if (trimmed.isEmpty) continue;
      final normalized = MerchantResolver.normalizeAlias(trimmed);
      if (normalized.isNotEmpty) result[normalized] = trimmed;
    }
    return result;
  }
}

final payeeLabelRepositoryProvider = FutureProvider<PayeeLabelRepository>(
  (ref) async =>
      PayeeLabelRepository(await ref.watch(appDatabaseProvider.future)),
);

final payeeIdentitiesProvider =
    StreamProvider<List<PayeeIdentity>>((ref) async* {
  final repository = await ref.watch(payeeLabelRepositoryProvider.future);
  yield* repository.watchIdentities();
});

final payeeIdentityPageProvider =
    StreamProvider.family<PayeeIdentityPage, PayeeIdentityQuery>(
        (ref, query) async* {
  final repository = await ref.watch(payeeLabelRepositoryProvider.future);
  yield* repository.watchPage(query);
});

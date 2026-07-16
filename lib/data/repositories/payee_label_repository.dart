import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  Stream<List<PayeeIdentity>> watchIdentities() {
    final query = _database.select(_database.transactions).join([
      leftOuterJoin(
        _database.merchants,
        _database.merchants.id.equalsExp(_database.transactions.merchantId),
      ),
    ])
      ..where(
        _database.transactions.isDeleted.equals(false) &
            _database.transactions.duplicateOfTxnId.isNull(),
      )
      ..orderBy([OrderingTerm.desc(_database.transactions.ts)]);

    return query.watch().map((rows) {
      final grouped = <String, _PayeeIdentityBuilder>{};
      for (final row in rows) {
        final transaction = row.readTable(_database.transactions);
        final merchant = row.readTableOrNull(_database.merchants);
        final evidence = <String>{
          if (_nonEmpty(transaction.merchantRaw) case final value?) value,
          if (_nonEmpty(transaction.counterpartyVpa) case final value?) value,
        };
        if (merchant == null && evidence.isEmpty) continue;
        final key = merchant != null
            ? 'merchant:${merchant.id}'
            : 'alias:${MerchantResolver.normalizeAlias(evidence.first)}';
        final builder = grouped.putIfAbsent(
          key,
          () => _PayeeIdentityBuilder(
            key: key,
            merchantId: merchant?.id,
            canonicalName: merchant?.canonicalName,
            userLabel: merchant?.userLabel,
          ),
        );
        builder.transactionCount += 1;
        builder.aliases.addAll(evidence);
      }
      final identities = grouped.values.map((value) => value.build()).toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
      return identities;
    });
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

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class _PayeeIdentityBuilder {
  _PayeeIdentityBuilder({
    required this.key,
    required this.merchantId,
    required this.canonicalName,
    required this.userLabel,
  });

  final String key;
  final String? merchantId;
  final String? canonicalName;
  final String? userLabel;
  final Set<String> aliases = {};
  int transactionCount = 0;

  PayeeIdentity build() => PayeeIdentity(
        key: key,
        merchantId: merchantId,
        userLabel: userLabel,
        displayName: userLabel ?? canonicalName ?? aliases.first,
        aliases: aliases.toList(growable: false)..sort(),
        transactionCount: transactionCount,
      );
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

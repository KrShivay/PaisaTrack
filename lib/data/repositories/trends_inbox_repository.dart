import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:drift/drift.dart' show Value;

import '../../core/constants.dart';
import '../../data/db/database.dart';
import '../../intelligence/claim.dart';

const trendsInboxModelMetaKey = 'trends_inbox_v1';
const trendsInboxBackupMetaKey = 'trends_inbox_v1_backup';
const inboxEnabled = true;

enum TrendsInboxState { newItem, seen, moved, cleared }

class TrendsInboxItem {
  const TrendsInboxItem({
    required this.key,
    required this.state,
    required this.isCurrent,
    required this.insight,
    required this.claim,
  });

  final String key;
  final TrendsInboxState state;
  final bool isCurrent;
  final Insight insight;
  final TypedClaim claim;
}

class TrendsInboxUndo {
  const TrendsInboxUndo(this.previousStates);

  final Map<String, TrendsInboxState> previousStates;
}

/// Stores only validated typed-claim snapshots and inbox state in model_meta.
///
/// Every mutation runs in its own drift transaction on a per-database serial
/// queue, so callers must not await these methods from inside another drift
/// transaction (the outer transaction would hold the connection).
class TrendsInboxRepository {
  TrendsInboxRepository(this._database);

  static final Expando<_InboxSerialQueue> _queues =
      Expando<_InboxSerialQueue>('trends inbox database queues');

  final AppDatabase _database;

  _InboxSerialQueue get _queue => _queues[_database] ??= _InboxSerialQueue();

  Future<List<TrendsInboxItem>> reconcile({
    required String period,
    required Iterable<Insight> freshClaims,
  }) =>
      _queue.run(
        () => _database.transaction(() async {
          final data = await _read();
          final items = data.items;
          _pruneExpired(items, period);
          for (final entry in items.entries.toList()) {
            final item = _parseItem(entry.key, entry.value);
            if (item == null ||
                item.insight.period != period ||
                !item.isCurrent) {
              continue;
            }
            items[entry.key] = _encodeItem(
              _toStored(item).copyWith(isCurrent: false),
            );
          }

          for (final insight in freshClaims) {
            final claim = const ClaimValidator().parse(insight);
            if (claim == null || insight.period != period) continue;
            final key = _key(insight, claim);
            final old = _parseItem(key, items[key]);
            final state = old?.state ?? TrendsInboxState.newItem;
            final safeInsight = Insight(
              id: insight.id,
              period: insight.period,
              kind: insight.kind,
              payloadJson: jsonEncode({'claim': claim.raw}),
              dismissed: false,
            );
            items[key] = _encodeItem(
              _StoredInboxItem(
                key: key,
                state: state,
                isCurrent: true,
                insight: safeInsight,
              ),
            );
          }
          await _writeIfChanged(data);
          return _itemsForPeriod(data, period);
        }),
      );

  /// Every retained item across periods (current, past, Later and cleared).
  Future<List<TrendsInboxItem>> readAll() => _queue.run(
        () => _database.transaction(() async {
          final data = await _read();
          return _itemsForPeriod(data, null);
        }),
      );

  Future<List<TrendsInboxItem>> readPeriod(String period) => _queue.run(
        () => _database.transaction(() async {
          final data = await _read();
          return _itemsForPeriod(data, period);
        }),
      );

  Future<void> markSeen(String key) => _updateItem(key, (item) {
        if (item.state == TrendsInboxState.newItem) {
          return item.copyWith(state: TrendsInboxState.seen);
        }
        return item;
      });

  Future<void> moveToLater(String key) => _updateItem(
        key,
        (item) => item.copyWith(state: TrendsInboxState.moved),
      );

  Future<void> returnToSeen(String key) => _updateItem(
        key,
        (item) => item.copyWith(state: TrendsInboxState.seen),
      );

  /// Restores a cleared item to `seen` and un-dismisses its source insight.
  /// Non-cleared or unknown keys are left untouched.
  Future<void> restore(String key) => _queue.run(
        () => _database.transaction(() async {
          final data = await _read();
          final item = _parseItem(key, data.items[key]);
          if (item == null || item.state != TrendsInboxState.cleared) return;
          data.items[key] = _encodeItem(
            _toStored(item).copyWith(state: TrendsInboxState.seen),
          );
          await (_database.update(_database.insights)
                ..where((row) => row.id.equals(item.insight.id)))
              .write(const InsightsCompanion(dismissed: Value(false)));
          await _writeIfChanged(data);
        }),
      );

  Future<void> clear(String key) => _clearItems({key});

  Future<void> clearClaim(String insightId) => _queue.run(
        () => _database.transaction(() async {
          final data = await _read();
          final matches = _itemsForPeriod(data, null)
              .where((item) => item.insight.id == insightId)
              .map((item) => item.key)
              .toSet();
          if (matches.isNotEmpty) {
            await _clearItemsInTransaction(data, matches);
            await _writeIfChanged(data);
            return;
          }
          await (_database.update(_database.insights)
                ..where((row) => row.id.equals(insightId)))
              .write(const InsightsCompanion(dismissed: Value(true)));
        }),
      );

  Future<TrendsInboxUndo> clearAll({required String period}) => _queue.run(
        () => _database.transaction(() async {
          final data = await _read();
          final visible = _itemsForPeriod(data, period)
              .where((item) => item.isCurrent)
              .toList(growable: false);
          final previous = {
            for (final item in visible)
              if (item.state != TrendsInboxState.cleared) item.key: item.state,
          };
          await _clearItemsInTransaction(data, previous.keys.toSet());
          await _writeIfChanged(data);
          return TrendsInboxUndo(previous);
        }),
      );

  Future<void> undoClearAll(TrendsInboxUndo undo) => _queue.run(
        () => _database.transaction(() async {
          final data = await _read();
          for (final entry in undo.previousStates.entries) {
            final item = _parseItem(entry.key, data.items[entry.key]);
            if (item == null || item.state != TrendsInboxState.cleared) {
              continue;
            }
            data.items[entry.key] =
                _encodeItem(_toStored(item).copyWith(state: entry.value));
            await (_database.update(_database.insights)
                  ..where((row) => row.id.equals(item.insight.id)))
                .write(const InsightsCompanion(dismissed: Value(false)));
          }
          await _writeIfChanged(data);
        }),
      );

  Future<void> _clearItems(Set<String> keys) => _queue.run(
        () => _database.transaction(() async {
          if (keys.isEmpty) return;
          final data = await _read();
          await _clearItemsInTransaction(data, keys);
          await _writeIfChanged(data);
        }),
      );

  Future<void> _updateItem(
    String key,
    _StoredInboxItem Function(_StoredInboxItem) update,
  ) =>
      _queue.run(
        () => _database.transaction(() async {
          final data = await _read();
          final item = _parseItem(key, data.items[key]);
          if (item == null) return;
          data.items[key] = _encodeItem(update(_toStored(item)));
          await _writeIfChanged(data);
        }),
      );

  Future<void> _clearItemsInTransaction(
    _InboxData data,
    Set<String> keys,
  ) async {
    for (final key in keys) {
      final item = _parseItem(key, data.items[key]);
      if (item == null) continue;
      data.items[key] = _encodeItem(
        _toStored(item).copyWith(state: TrendsInboxState.cleared),
      );
      await (_database.update(_database.insights)
            ..where((row) => row.id.equals(item.insight.id)))
          .write(const InsightsCompanion(dismissed: Value(true)));
    }
  }

  List<TrendsInboxItem> _itemsForPeriod(_InboxData data, String? period) => [
        for (final entry in data.items.entries)
          if (_parseItem(entry.key, entry.value) case final item?)
            if (period == null || item.insight.period == period) item,
      ]..sort(_compareItems);

  void _pruneExpired(Map<String, Map<String, dynamic>> items, String period) {
    final selected = _monthStart(period);
    if (selected == null) return;
    final now = DateTime.now();
    final current = DateTime(now.year, now.month);
    final anchor = selected.isAfter(current) ? selected : current;
    final cutoff = DateTime(
      anchor.year,
      anchor.month - AppConstants.trendsInboxRetentionMonths,
    );
    items.removeWhere((key, json) {
      final rawInsight = json['insight'];
      final itemPeriod =
          rawInsight is Map<String, dynamic> ? rawInsight['period'] : null;
      final month = itemPeriod is String ? _monthStart(itemPeriod) : null;
      return month == null || month.isBefore(cutoff) || month.isAfter(anchor);
    });
  }

  DateTime? _monthStart(String period) {
    final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(period);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    if (month < 1 || month > 12) return null;
    return DateTime(year, month);
  }

  Future<_InboxData> _read() async {
    final row = await (_database.select(_database.modelMeta)
          ..where((meta) => meta.key.equals(trendsInboxModelMetaKey)))
        .getSingleOrNull();
    if (row == null) return _InboxData({});
    try {
      final json = jsonDecode(row.value);
      if (json is! Map<String, dynamic> || json['v'] != 1) {
        await _preserveCorrupt(row.value, 'unsupported or malformed root');
        return _InboxData({});
      }
      final rawItems = json['items'];
      if (rawItems is! Map<String, dynamic>) {
        await _preserveCorrupt(row.value, 'items field is malformed');
        return _InboxData({});
      }
      if (rawItems.values.any((item) => item is! Map<String, dynamic>)) {
        await _preserveCorrupt(row.value, 'an item entry is malformed');
        return _InboxData({});
      }
      final items = {
        for (final entry in rawItems.entries)
          entry.key: Map<String, dynamic>.from(entry.value as Map),
      };
      if (items.entries
          .any((entry) => _parseItem(entry.key, entry.value) == null)) {
        await _preserveCorrupt(row.value, 'an item payload is invalid');
        return _InboxData({});
      }
      return _InboxData(items);
    } on Object {
      await _preserveCorrupt(row.value, 'JSON could not be decoded');
      return _InboxData({});
    }
  }

  Future<void> _preserveCorrupt(String raw, String reason) async {
    final backup = await (_database.select(_database.modelMeta)
          ..where((meta) => meta.key.equals(trendsInboxBackupMetaKey)))
        .getSingleOrNull();
    if (backup == null) {
      await _database.into(_database.modelMeta).insert(
            ModelMetaCompanion.insert(
              key: trendsInboxBackupMetaKey,
              value: raw,
            ),
          );
    }
    developer.log(
      'Preserved Trends inbox metadata backup ($reason).',
      name: 'PaisaTrack.TrendsInboxRepository',
      level: 900,
    );
  }

  Future<void> _writeIfChanged(_InboxData data) async {
    final value = jsonEncode({'v': 1, 'items': data.items});
    final old = await (_database.select(_database.modelMeta)
          ..where((meta) => meta.key.equals(trendsInboxModelMetaKey)))
        .getSingleOrNull();
    if (old?.value == value) return;
    await _database.into(_database.modelMeta).insertOnConflictUpdate(
          ModelMetaCompanion.insert(
            key: trendsInboxModelMetaKey,
            value: value,
          ),
        );
  }

  String _key(Insight insight, TypedClaim claim) {
    final scope = _canonicalize(claim.scope);
    return jsonEncode([insight.kind, scope, insight.period]);
  }

  Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonicalize(value[key])};
    }
    if (value is List) {
      final values = value.map(_canonicalize).toList();
      if (values.every((element) => element is String)) {
        values.sort((a, b) => (a as String).compareTo(b as String));
      }
      return values;
    }
    return value;
  }

  Map<String, dynamic> _encodeItem(_StoredInboxItem item) => {
        'state': _stateName(item.state),
        'current': item.isCurrent,
        'insight': {
          'id': item.insight.id,
          'period': item.insight.period,
          'kind': item.insight.kind,
          'payload': item.insight.payloadJson,
          'dismissed': item.insight.dismissed,
        },
      };

  TrendsInboxItem? _parseItem(String key, Map<String, dynamic>? json) {
    if (json == null) return null;
    try {
      final rawInsight = json['insight'] as Map<String, dynamic>;
      final insight = Insight(
        id: rawInsight['id'] as String,
        period: rawInsight['period'] as String,
        kind: rawInsight['kind'] as String,
        payloadJson: rawInsight['payload'] as String,
        dismissed: rawInsight['dismissed'] as bool,
      );
      final claim = const ClaimValidator().parse(insight);
      final state = _parseState(json['state'] as String);
      if (claim == null) return null;
      return TrendsInboxItem(
        key: key,
        state: state,
        isCurrent: json['current'] as bool,
        insight: insight,
        claim: claim,
      );
    } on Object {
      return null;
    }
  }

  _StoredInboxItem _toStored(TrendsInboxItem item) => _StoredInboxItem(
        key: item.key,
        state: item.state,
        isCurrent: item.isCurrent,
        insight: item.insight,
      );

  String _stateName(TrendsInboxState state) => switch (state) {
        TrendsInboxState.newItem => 'new',
        TrendsInboxState.seen => 'seen',
        TrendsInboxState.moved => 'moved',
        TrendsInboxState.cleared => 'cleared',
      };

  TrendsInboxState _parseState(String state) => switch (state) {
        'new' => TrendsInboxState.newItem,
        'seen' => TrendsInboxState.seen,
        'moved' => TrendsInboxState.moved,
        'cleared' => TrendsInboxState.cleared,
        _ => throw FormatException('Unknown Trends inbox state: $state'),
      };

  int _compareItems(TrendsInboxItem a, TrendsInboxItem b) {
    int rank(TrendsInboxState state) => switch (state) {
          TrendsInboxState.newItem => 0,
          TrendsInboxState.seen => 0,
          TrendsInboxState.moved => 1,
          TrendsInboxState.cleared => 2,
        };
    final rankComparison = rank(a.state).compareTo(rank(b.state));
    return rankComparison == 0 ? a.key.compareTo(b.key) : rankComparison;
  }
}

class _InboxSerialQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

class _InboxData {
  _InboxData(this.items);

  final Map<String, Map<String, dynamic>> items;
}

class _StoredInboxItem {
  const _StoredInboxItem({
    required this.key,
    required this.state,
    required this.isCurrent,
    required this.insight,
  });

  final String key;
  final TrendsInboxState state;
  final bool isCurrent;
  final Insight insight;

  _StoredInboxItem copyWith({
    TrendsInboxState? state,
    bool? isCurrent,
  }) =>
      _StoredInboxItem(
        key: key,
        state: state ?? this.state,
        isCurrent: isCurrent ?? this.isCurrent,
        insight: insight,
      );
}

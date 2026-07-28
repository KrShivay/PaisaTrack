import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../data/db/database.dart';

/// Stored `model_meta` key for the ADR 0005 public-template trust ledger.
const templateTrustLedgerMetaKey = 'template_trust_ledger_v1';

/// Trust state derived from parse-confirmation feedback for one template.
///
/// Only public-provenance template transactions contribute. A corrected amount
/// or direction is a durable safety signal: the template remains demoted until
/// it is re-authored under a new template id.
class TemplateTrustEntry {
  const TemplateTrustEntry({
    required this.templateId,
    required this.confirmedParses,
    required this.amountCorrections,
    required this.directionCorrections,
  });

  final String templateId;
  final int confirmedParses;
  final int amountCorrections;
  final int directionCorrections;

  /// Amount/direction corrections are the promotion-blocking safety signal.
  int get amountDirectionCorrections =>
      amountCorrections + directionCorrections;

  /// ADR 0005 promotion threshold for public-provenance templates.
  bool get isPromoted =>
      confirmedParses >= 20 && amountDirectionCorrections == 0;

  /// A demoted template must be visible to developers for re-authoring.
  bool get isFlagged => amountDirectionCorrections > 0;

  Map<String, Object> toJson() => {
        'confirmed_parses': confirmedParses,
        'amount_corrections': amountCorrections,
        'direction_corrections': directionCorrections,
      };

  static TemplateTrustEntry? fromJson(String templateId, Object? value) {
    if (value is! Map<String, Object?>) return null;
    final confirmed = value['confirmed_parses'];
    final amount = value['amount_corrections'];
    final direction = value['direction_corrections'];
    if (confirmed is! num || amount is! num || direction is! num) return null;
    return TemplateTrustEntry(
      templateId: templateId,
      confirmedParses: confirmed.toInt(),
      amountCorrections: amount.toInt(),
      directionCorrections: direction.toInt(),
    );
  }
}

/// Persisted, parse-time view of public-template trust.
class TemplateTrustLedgerSnapshot {
  const TemplateTrustLedgerSnapshot(this.entries);

  final Map<String, TemplateTrustEntry> entries;

  /// IDs requiring a template-authoring investigation in the dev screen.
  List<TemplateTrustEntry> get flaggedEntries =>
      entries.values.where((entry) => entry.isFlagged).toList(growable: false)
        ..sort((a, b) => a.templateId.compareTo(b.templateId));

  Map<String, Object> toJson() => {
        'version': 1,
        'templates': entries.map((id, entry) => MapEntry(id, entry.toJson())),
      };

  static TemplateTrustLedgerSnapshot fromJson(String value) {
    try {
      final decoded = jsonDecode(value) as Map<String, Object?>;
      final templates = decoded['templates'];
      if (templates is! Map<String, Object?>) {
        return const TemplateTrustLedgerSnapshot({});
      }
      final entries = <String, TemplateTrustEntry>{};
      for (final entry in templates.entries) {
        final parsed = TemplateTrustEntry.fromJson(entry.key, entry.value);
        if (parsed != null) entries[entry.key] = parsed;
      }
      return TemplateTrustLedgerSnapshot(entries);
    } on FormatException {
      return const TemplateTrustLedgerSnapshot({});
    } on TypeError {
      return const TemplateTrustLedgerSnapshot({});
    }
  }
}

/// Rebuilds public-template confidence from `parse_verdict` feedback rows.
///
/// The feedback table remains the source of truth. `model_meta` only stores a
/// compact, parse-time cache so SMS matching never needs to inspect historical
/// transaction feedback beyond a single metadata read.
class TemplateTrustLedger {
  const TemplateTrustLedger(this._database);

  final AppDatabase _database;

  /// Reads the persisted ledger, defaulting unknown public templates to 0.85.
  Future<double> confidenceForTemplate(String templateId) async {
    final snapshot = await load();
    return snapshot.entries[templateId]?.isPromoted == true
        ? AppConstants.promotedTemplateConfidence
        : AppConstants.defaultTemplateConfidence;
  }

  /// Recomputes counters from feedback and atomically updates `model_meta`.
  Future<TemplateTrustLedgerSnapshot> refresh() async {
    final query = _database.select(_database.feedback).join([
      innerJoin(
        _database.transactions,
        _database.transactions.id.equalsExp(_database.feedback.txnId),
      ),
    ])
      ..where(
        _database.feedback.field.equals('parse_verdict') &
            _database.feedback.context.equals('parse_confirm'),
      );
    final counts = <String, _TemplateTrustCounts>{};

    for (final row in await query.get()) {
      final templateId = _publicTemplateId(
        row.readTable(_database.transactions).confidenceJson,
      );
      if (templateId == null) continue;
      final feedback = row.readTable(_database.feedback);
      final count = counts.putIfAbsent(templateId, _TemplateTrustCounts.new);
      switch (feedback.newValue) {
        case 'ok':
          count.confirmedParses++;
        case 'amount_corrected':
          count.amountCorrections++;
        case 'direction_corrected':
          count.directionCorrections++;
      }
    }

    final snapshot = TemplateTrustLedgerSnapshot({
      for (final entry in counts.entries)
        entry.key: TemplateTrustEntry(
          templateId: entry.key,
          confirmedParses: entry.value.confirmedParses,
          amountCorrections: entry.value.amountCorrections,
          directionCorrections: entry.value.directionCorrections,
        ),
    });
    await _database.into(_database.modelMeta).insertOnConflictUpdate(
          ModelMetaCompanion.insert(
            key: templateTrustLedgerMetaKey,
            value: jsonEncode(snapshot.toJson()),
          ),
        );
    return snapshot;
  }

  /// Reads the cache without traversing feedback, for the parse hot path.
  Future<TemplateTrustLedgerSnapshot> load() async {
    final row = await (_database.select(_database.modelMeta)
          ..where((meta) => meta.key.equals(templateTrustLedgerMetaKey)))
        .getSingleOrNull();
    return row == null
        ? const TemplateTrustLedgerSnapshot({})
        : TemplateTrustLedgerSnapshot.fromJson(row.value);
  }

  /// Watches the persisted cache so developer diagnostics update after a
  /// parse correction without requiring a screen reload.
  Stream<TemplateTrustLedgerSnapshot> watch() {
    return (_database.select(_database.modelMeta)
          ..where((meta) => meta.key.equals(templateTrustLedgerMetaKey)))
        .watchSingleOrNull()
        .map(
          (row) => row == null
              ? const TemplateTrustLedgerSnapshot({})
              : TemplateTrustLedgerSnapshot.fromJson(row.value),
        );
  }
}

String? _publicTemplateId(String confidenceJson) {
  try {
    final decoded = jsonDecode(confidenceJson) as Map<String, Object?>;
    final parser = decoded['parser'] as Map<String, Object?>?;
    if (parser?['provenance'] != 'public') return null;
    final templateId = parser?['template_id'];
    return templateId is String && templateId.isNotEmpty ? templateId : null;
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}

class _TemplateTrustCounts {
  int confirmedParses = 0;
  int amountCorrections = 0;
  int directionCorrections = 0;
}

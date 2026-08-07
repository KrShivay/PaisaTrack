import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants.dart';
import '../db/database.dart';
import '../db/database_provider.dart';

/// Key definitions for feature flags and thresholds.
abstract class FeatureFlagKeys {
  static const enableLocalLlm = 'enable_local_llm';
  static const enableNarrativeInsights = 'enable_narrative_insights';
  static const silentConfidenceThreshold = 'silent_confidence_threshold';
  static const askConfidenceThreshold = 'ask_confidence_threshold';
  static const askNowDailyBudget = 'ask_now_daily_budget';
  static const askAmountThreshold = 'ask_amount_threshold';
  static const askMerchantTxnCount = 'ask_merchant_txn_count';
  static const rawSmsRetentionDays = 'raw_sms_retention_days';
  static const smsHistoryImportPageSize = 'sms_history_import_page_size';
  static const duplicatePairWindowMinutes = 'duplicate_pair_window_minutes';
  static const merchantAutoLinkThreshold = 'merchant_auto_link_threshold';
  static const merchantClusterSuggestionThreshold =
      'merchant_cluster_suggestion_threshold';
  static const llmCategorySuggestionCap = 'llm_category_suggestion_cap';
  static const refundAutoLinkThreshold = 'refund_auto_link_threshold';
  static const authSettleLinkThreshold = 'auth_settle_link_threshold';
  static const expectedDebitFulfilmentThreshold =
      'expected_debit_fulfilment_threshold';
  static const anomalyAlertSigma = 'anomaly_alert_sigma';
  static const anomalyAlertMinPeriods = 'anomaly_alert_min_periods';
  static const anomalyAlertFloorAmount = 'anomaly_alert_floor_amount';
}

enum FeatureFlagValueType { boolean, integer, decimal }

/// Metadata used by the developer editor and default seeding checks.
class FeatureFlagDefinition {
  const FeatureFlagDefinition({
    required this.key,
    required this.label,
    required this.description,
    required this.type,
    required this.defaultValue,
  });

  final String key;
  final String label;
  final String description;
  final FeatureFlagValueType type;
  final Object defaultValue;

  String get defaultText => defaultValue.toString();
}

const featureFlagDefinitions = <FeatureFlagDefinition>[
  FeatureFlagDefinition(
    key: FeatureFlagKeys.enableLocalLlm,
    label: 'Local LLM parsing',
    description: 'Allow on-device language-model parsing when available.',
    type: FeatureFlagValueType.boolean,
    defaultValue: AppConstants.enableLocalLlm,
  ),
  FeatureFlagDefinition(
    key: FeatureFlagKeys.enableNarrativeInsights,
    label: 'Narrative insights',
    description: 'Allow local narrative insight generation when available.',
    type: FeatureFlagValueType.boolean,
    defaultValue: AppConstants.enableNarrativeInsights,
  ),
  FeatureFlagDefinition(
    key: FeatureFlagKeys.silentConfidenceThreshold,
    label: 'Silent auto-label',
    description: 'Minimum confidence for automatic labels without asking.',
    type: FeatureFlagValueType.decimal,
    defaultValue: AppConstants.silentConfidenceThreshold,
  ),
  FeatureFlagDefinition(
    key: FeatureFlagKeys.askConfidenceThreshold,
    label: 'Ask confidence',
    description: 'Minimum confidence before a transaction can be clarified.',
    type: FeatureFlagValueType.decimal,
    defaultValue: AppConstants.askConfidenceThreshold,
  ),
  FeatureFlagDefinition(
    key: FeatureFlagKeys.askNowDailyBudget,
    label: 'Ask budget',
    description: 'Maximum clarification prompts per day.',
    type: FeatureFlagValueType.integer,
    defaultValue: AppConstants.askNowDailyBudget,
  ),
  FeatureFlagDefinition(
    key: FeatureFlagKeys.askAmountThreshold,
    label: 'Ask amount threshold',
    description: 'Amount that makes a mid-confidence transaction worth asking.',
    type: FeatureFlagValueType.decimal,
    defaultValue: AppConstants.askAmountThreshold,
  ),
  FeatureFlagDefinition(
    key: FeatureFlagKeys.askMerchantTxnCount,
    label: 'Ask merchant history',
    description: 'Prior merchant count that makes asking worthwhile.',
    type: FeatureFlagValueType.integer,
    defaultValue: AppConstants.askMerchantTxnCount,
  ),
  FeatureFlagDefinition(
    key: FeatureFlagKeys.rawSmsRetentionDays,
    label: 'Raw SMS retention',
    description: 'Days raw SMS bodies may remain before purge.',
    type: FeatureFlagValueType.integer,
    defaultValue: AppConstants.rawSmsRetentionDays,
  ),
  FeatureFlagDefinition(
    key: FeatureFlagKeys.smsHistoryImportPageSize,
    label: 'History import page size',
    description: 'Raw inbox rows requested per history-import page.',
    type: FeatureFlagValueType.integer,
    defaultValue: AppConstants.smsHistoryImportPageSize,
  ),
  FeatureFlagDefinition(
    key: FeatureFlagKeys.duplicatePairWindowMinutes,
    label: 'Duplicate pair window',
    description: 'Maximum minutes between paired bank and wallet alerts.',
    type: FeatureFlagValueType.integer,
    defaultValue: AppConstants.duplicatePairWindowMinutes,
  ),
  FeatureFlagDefinition(
    key: FeatureFlagKeys.merchantAutoLinkThreshold,
    label: 'Merchant auto-link',
    description: 'Similarity needed to link a merchant automatically.',
    type: FeatureFlagValueType.decimal,
    defaultValue: AppConstants.merchantAutoLinkThreshold,
  ),
  FeatureFlagDefinition(
    key: FeatureFlagKeys.merchantClusterSuggestionThreshold,
    label: 'Merchant cluster suggestion',
    description: 'Similarity needed to suggest a merchant cluster.',
    type: FeatureFlagValueType.decimal,
    defaultValue: AppConstants.merchantClusterSuggestionThreshold,
  ),
  FeatureFlagDefinition(
    key: FeatureFlagKeys.llmCategorySuggestionCap,
    label: 'LLM category cap',
    description:
        'Maximum confidence contributed by an LLM category suggestion.',
    type: FeatureFlagValueType.decimal,
    defaultValue: AppConstants.llmCategorySuggestionCap,
  ),
  FeatureFlagDefinition(
    key: FeatureFlagKeys.refundAutoLinkThreshold,
    label: 'Refund auto-link',
    description: 'Confidence needed to link a refund automatically.',
    type: FeatureFlagValueType.decimal,
    defaultValue: AppConstants.refundAutoLinkThreshold,
  ),
  FeatureFlagDefinition(
    key: FeatureFlagKeys.authSettleLinkThreshold,
    label: 'Auth → settle link',
    description: 'Confidence needed to link authorization and settlement.',
    type: FeatureFlagValueType.decimal,
    defaultValue: AppConstants.authSettleLinkThreshold,
  ),
  FeatureFlagDefinition(
    key: FeatureFlagKeys.expectedDebitFulfilmentThreshold,
    label: 'Expected debit fulfilment',
    description: 'Confidence needed to fulfil an expected debit event.',
    type: FeatureFlagValueType.decimal,
    defaultValue: AppConstants.expectedDebitFulfilmentThreshold,
  ),
  FeatureFlagDefinition(
    key: FeatureFlagKeys.anomalyAlertSigma,
    label: 'Anomaly sigma',
    description: 'Standard-deviation multiplier for anomaly alerts.',
    type: FeatureFlagValueType.decimal,
    defaultValue: AppConstants.anomalyAlertSigma,
  ),
  FeatureFlagDefinition(
    key: FeatureFlagKeys.anomalyAlertMinPeriods,
    label: 'Anomaly history periods',
    description: 'Minimum historical periods before anomaly alerts.',
    type: FeatureFlagValueType.integer,
    defaultValue: AppConstants.anomalyAlertMinPeriods,
  ),
  FeatureFlagDefinition(
    key: FeatureFlagKeys.anomalyAlertFloorAmount,
    label: 'Anomaly amount floor',
    description: 'Minimum aggregate amount for anomaly alerts.',
    type: FeatureFlagValueType.decimal,
    defaultValue: AppConstants.anomalyAlertFloorAmount,
  ),
];

/// Immutable state containing active feature flags and thresholds.
///
/// If a key is missing from the database, it falls back to the corresponding
/// value in [AppConstants].
@immutable
class FeatureFlagsState {
  FeatureFlagsState(Map<String, String> dbValues)
      : _overrides = Map.unmodifiable(dbValues);

  final Map<String, String> _overrides;

  /// Raw overrides map present in the database.
  Map<String, String> get overrides => _overrides;

  /// Returns the typed effective value for a definition.
  Object valueFor(FeatureFlagDefinition definition) {
    final raw = _overrides[definition.key];
    if (raw == null) return definition.defaultValue;
    return switch (definition.type) {
      FeatureFlagValueType.boolean => _parseBool(
          raw,
          fallback: definition.defaultValue as bool,
        ),
      FeatureFlagValueType.integer =>
        int.tryParse(raw.trim()) ?? definition.defaultValue as int,
      FeatureFlagValueType.decimal =>
        double.tryParse(raw.trim()) ?? definition.defaultValue as double,
    };
  }

  bool isOverridden(FeatureFlagDefinition definition) =>
      _overrides.containsKey(definition.key);

  bool get enableLocalLlm => getBool(
        FeatureFlagKeys.enableLocalLlm,
        defaultValue: AppConstants.enableLocalLlm,
      );

  bool get enableNarrativeInsights => getBool(
        FeatureFlagKeys.enableNarrativeInsights,
        defaultValue: AppConstants.enableNarrativeInsights,
      );

  double get silentConfidenceThreshold => getDouble(
        FeatureFlagKeys.silentConfidenceThreshold,
        defaultValue: AppConstants.silentConfidenceThreshold,
      );

  double get askConfidenceThreshold => getDouble(
        FeatureFlagKeys.askConfidenceThreshold,
        defaultValue: AppConstants.askConfidenceThreshold,
      );

  int get askNowDailyBudget => getInt(
        FeatureFlagKeys.askNowDailyBudget,
        defaultValue: AppConstants.askNowDailyBudget,
      );

  double get askAmountThreshold => getDouble(
        FeatureFlagKeys.askAmountThreshold,
        defaultValue: AppConstants.askAmountThreshold,
      );

  int get askMerchantTxnCount => getInt(
        FeatureFlagKeys.askMerchantTxnCount,
        defaultValue: AppConstants.askMerchantTxnCount,
      );

  int get rawSmsRetentionDays => getInt(
        FeatureFlagKeys.rawSmsRetentionDays,
        defaultValue: AppConstants.rawSmsRetentionDays,
      );

  int get smsHistoryImportPageSize => getInt(
        FeatureFlagKeys.smsHistoryImportPageSize,
        defaultValue: AppConstants.smsHistoryImportPageSize,
      );

  int get duplicatePairWindowMinutes => getInt(
        FeatureFlagKeys.duplicatePairWindowMinutes,
        defaultValue: AppConstants.duplicatePairWindowMinutes,
      );

  double get merchantAutoLinkThreshold => getDouble(
        FeatureFlagKeys.merchantAutoLinkThreshold,
        defaultValue: AppConstants.merchantAutoLinkThreshold,
      );

  double get merchantClusterSuggestionThreshold => getDouble(
        FeatureFlagKeys.merchantClusterSuggestionThreshold,
        defaultValue: AppConstants.merchantClusterSuggestionThreshold,
      );

  double get llmCategorySuggestionCap => getDouble(
        FeatureFlagKeys.llmCategorySuggestionCap,
        defaultValue: AppConstants.llmCategorySuggestionCap,
      );

  double get refundAutoLinkThreshold => getDouble(
        FeatureFlagKeys.refundAutoLinkThreshold,
        defaultValue: AppConstants.refundAutoLinkThreshold,
      );

  double get authSettleLinkThreshold => getDouble(
        FeatureFlagKeys.authSettleLinkThreshold,
        defaultValue: AppConstants.authSettleLinkThreshold,
      );

  double get expectedDebitFulfilmentThreshold => getDouble(
        FeatureFlagKeys.expectedDebitFulfilmentThreshold,
        defaultValue: AppConstants.expectedDebitFulfilmentThreshold,
      );

  double get anomalyAlertSigma => getDouble(
        FeatureFlagKeys.anomalyAlertSigma,
        defaultValue: AppConstants.anomalyAlertSigma,
      );

  int get anomalyAlertMinPeriods => getInt(
        FeatureFlagKeys.anomalyAlertMinPeriods,
        defaultValue: AppConstants.anomalyAlertMinPeriods,
      );

  double get anomalyAlertFloorAmount => getDouble(
        FeatureFlagKeys.anomalyAlertFloorAmount,
        defaultValue: AppConstants.anomalyAlertFloorAmount,
      );

  /// Retrieves a boolean flag, falling back to [defaultValue] if missing or unparseable.
  bool getBool(String key, {required bool defaultValue}) {
    final val = _overrides[key];
    if (val == null) return defaultValue;
    return _parseBool(val, fallback: defaultValue);
  }

  /// Retrieves an integer flag, falling back to [defaultValue] if missing or unparseable.
  int getInt(String key, {required int defaultValue}) {
    final val = _overrides[key];
    if (val == null) return defaultValue;
    return int.tryParse(val.trim()) ?? defaultValue;
  }

  /// Retrieves a double flag, falling back to [defaultValue] if missing or unparseable.
  double getDouble(String key, {required double defaultValue}) {
    final val = _overrides[key];
    if (val == null) return defaultValue;
    return double.tryParse(val.trim()) ?? defaultValue;
  }

  /// Retrieves a string flag, falling back to [defaultValue] if missing.
  String getString(String key, {required String defaultValue}) {
    return _overrides[key] ?? defaultValue;
  }

  static bool _parseBool(String value, {required bool fallback}) {
    final lower = value.trim().toLowerCase();
    if (lower == 'true' || lower == '1') return true;
    if (lower == 'false' || lower == '0') return false;
    return fallback;
  }
}

/// Reactive repository for reading and writing feature flags to [AppDatabase].
class FeatureFlagRepository {
  FeatureFlagRepository(this._database);

  final AppDatabase _database;

  /// Yields active [FeatureFlagsState] whenever the `feature_flags` table changes.
  Stream<FeatureFlagsState> watchFlags() {
    return _database.select(_database.featureFlags).watch().map((rows) {
      final map = {for (final row in rows) row.key: row.value};
      return FeatureFlagsState(map);
    });
  }

  /// Reads current snapshot of [FeatureFlagsState].
  Future<FeatureFlagsState> getFlags() async {
    final rows = await _database.select(_database.featureFlags).get();
    final map = {for (final row in rows) row.key: row.value};
    return FeatureFlagsState(map);
  }

  /// Sets or updates a feature flag key-value pair.
  Future<void> setFlag(String key, String value) async {
    await _database.into(_database.featureFlags).insertOnConflictUpdate(
          FeatureFlagsCompanion.insert(
            key: key,
            value: value,
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }

  /// Sets a boolean flag.
  Future<void> setBool(String key, bool value) =>
      setFlag(key, value.toString());

  /// Sets an integer flag.
  Future<void> setInt(String key, int value) => setFlag(key, value.toString());

  /// Sets a double flag.
  Future<void> setDouble(String key, double value) =>
      setFlag(key, value.toString());

  /// Validates and stores a value entered by the developer editor.
  Future<void> setValue(FeatureFlagDefinition definition, String raw) async {
    final value = raw.trim();
    final valid = switch (definition.type) {
      FeatureFlagValueType.boolean => value == 'true' || value == 'false',
      FeatureFlagValueType.integer => int.tryParse(value) != null,
      FeatureFlagValueType.decimal => double.tryParse(value) != null,
    };
    if (!valid) {
      throw FormatException('Invalid value for ${definition.label}');
    }
    await setFlag(definition.key, value);
  }

  /// Removes a feature flag override from the database, falling back to [AppConstants].
  Future<void> resetFlag(String key) async {
    await (_database.delete(_database.featureFlags)
          ..where((t) => t.key.equals(key)))
        .go();
  }

  /// Clears all feature flag overrides.
  Future<void> resetAllFlags() async {
    await _database.delete(_database.featureFlags).go();
  }
}

/// Riverpod provider for [FeatureFlagRepository].
final featureFlagRepositoryProvider =
    FutureProvider<FeatureFlagRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return FeatureFlagRepository(db);
});

/// Riverpod StreamProvider that yields active [FeatureFlagsState] reactively.
///
/// Consumers reading this provider should handle `.when(error: ...)` to handle
/// database initialization failures or underlying stream errors safely.
final featureFlagsStreamProvider =
    StreamProvider<FeatureFlagsState>((ref) async* {
  final repo = await ref.watch(featureFlagRepositoryProvider.future);
  yield* repo.watchFlags();
});

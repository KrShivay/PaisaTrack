import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/constants.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/repositories/feature_flag_repository.dart';

void main() {
  late AppDatabase db;
  late FeatureFlagRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = FeatureFlagRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('FeatureFlagRepository Fallbacks & Overrides', () {
    test('missing DB rows fall back to AppConstants defaults', () async {
      final flags = await repository.getFlags();

      expect(flags.enableLocalLlm, AppConstants.enableLocalLlm);
      expect(flags.enableNarrativeInsights, AppConstants.enableNarrativeInsights);
      expect(flags.silentConfidenceThreshold, AppConstants.silentConfidenceThreshold);
      expect(flags.askConfidenceThreshold, AppConstants.askConfidenceThreshold);
      expect(flags.askNowDailyBudget, AppConstants.askNowDailyBudget);
      expect(flags.askAmountThreshold, AppConstants.askAmountThreshold);
      expect(flags.askMerchantTxnCount, AppConstants.askMerchantTxnCount);
      expect(flags.rawSmsRetentionDays, AppConstants.rawSmsRetentionDays);
      expect(flags.smsHistoryImportPageSize, AppConstants.smsHistoryImportPageSize);
      expect(flags.duplicatePairWindowMinutes, AppConstants.duplicatePairWindowMinutes);
      expect(flags.merchantAutoLinkThreshold, AppConstants.merchantAutoLinkThreshold);
      expect(flags.merchantClusterSuggestionThreshold, AppConstants.merchantClusterSuggestionThreshold);
      expect(flags.llmCategorySuggestionCap, AppConstants.llmCategorySuggestionCap);
      expect(flags.refundAutoLinkThreshold, AppConstants.refundAutoLinkThreshold);
      expect(flags.authSettleLinkThreshold, AppConstants.authSettleLinkThreshold);
      expect(flags.expectedDebitFulfilmentThreshold, AppConstants.expectedDebitFulfilmentThreshold);
      expect(flags.anomalyAlertSigma, AppConstants.anomalyAlertSigma);
      expect(flags.anomalyAlertMinPeriods, AppConstants.anomalyAlertMinPeriods);
      expect(flags.anomalyAlertFloorAmount, AppConstants.anomalyAlertFloorAmount);
    });

    test('setting a flag override updates the flag value', () async {
      await repository.setDouble(FeatureFlagKeys.silentConfidenceThreshold, 0.85);
      await repository.setBool(FeatureFlagKeys.enableLocalLlm, false);
      await repository.setInt(FeatureFlagKeys.askNowDailyBudget, 5);

      final flags = await repository.getFlags();

      expect(flags.silentConfidenceThreshold, 0.85);
      expect(flags.enableLocalLlm, false);
      expect(flags.askNowDailyBudget, 5);
      // Unmodified flag remains fallback
      expect(flags.askConfidenceThreshold, AppConstants.askConfidenceThreshold);
    });

    test('resetting a flag reverts it back to AppConstants fallback', () async {
      await repository.setDouble(FeatureFlagKeys.silentConfidenceThreshold, 0.85);
      var flags = await repository.getFlags();
      expect(flags.silentConfidenceThreshold, 0.85);

      await repository.resetFlag(FeatureFlagKeys.silentConfidenceThreshold);
      flags = await repository.getFlags();
      expect(flags.silentConfidenceThreshold, AppConstants.silentConfidenceThreshold);
    });

    test('resetAllFlags clears all DB overrides', () async {
      await repository.setDouble(FeatureFlagKeys.silentConfidenceThreshold, 0.85);
      await repository.setBool(FeatureFlagKeys.enableLocalLlm, false);

      await repository.resetAllFlags();
      final flags = await repository.getFlags();

      expect(flags.silentConfidenceThreshold, AppConstants.silentConfidenceThreshold);
      expect(flags.enableLocalLlm, AppConstants.enableLocalLlm);
      expect(flags.overrides, isEmpty);
    });

    test('unparseable string values fall back safely to AppConstants defaults', () async {
      await repository.setFlag(FeatureFlagKeys.silentConfidenceThreshold, 'not_a_number');
      await repository.setFlag(FeatureFlagKeys.enableLocalLlm, 'maybe');
      await repository.setFlag(FeatureFlagKeys.askNowDailyBudget, 'three');

      final flags = await repository.getFlags();

      expect(flags.silentConfidenceThreshold, AppConstants.silentConfidenceThreshold);
      expect(flags.enableLocalLlm, AppConstants.enableLocalLlm);
      expect(flags.askNowDailyBudget, AppConstants.askNowDailyBudget);
    });

    test('watchFlags stream emits updated FeatureFlagsState reactively on DB edit', () async {
      final stream = repository.watchFlags().asBroadcastStream();

      // 1. Initial emission
      final initial = await stream.first;
      expect(initial.silentConfidenceThreshold, AppConstants.silentConfidenceThreshold);

      // 2. Edit flag -> emission 2
      final secondFuture = stream.first;
      await repository.setDouble(FeatureFlagKeys.silentConfidenceThreshold, 0.75);
      final second = await secondFuture;
      expect(second.silentConfidenceThreshold, 0.75);

      // 3. Reset flag -> emission 3
      final thirdFuture = stream.first;
      await repository.resetFlag(FeatureFlagKeys.silentConfidenceThreshold);
      final third = await thirdFuture;
      expect(third.silentConfidenceThreshold, AppConstants.silentConfidenceThreshold);
    });

    test('Riverpod providers expose feature flag repository and reactive stream', () async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => db),
        ],
      );
      addTearDown(container.dispose);

      final repo = await container.read(featureFlagRepositoryProvider.future);
      expect(repo, isNotNull);

      final flagsState = await container.read(featureFlagsStreamProvider.future);
      expect(flagsState.silentConfidenceThreshold, AppConstants.silentConfidenceThreshold);
    });
  });
}

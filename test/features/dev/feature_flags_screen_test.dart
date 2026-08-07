import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/feature_flag_repository.dart';
import 'package:paisatrack/features/dev/feature_flags_screen.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Widget buildSubject() {
    return ProviderScope(
      overrides: [
        featureFlagRepositoryProvider.overrideWith(
          (ref) async => FeatureFlagRepository(database),
        ),
        featureFlagsStreamProvider.overrideWith(
          (ref) => Stream.value(FeatureFlagsState(const {})),
        ),
      ],
      child: const MaterialApp(home: FeatureFlagsScreen()),
    );
  }

  testWidgets('renders the feature flag catalogue', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    expect(find.text('Feature flags'), findsOneWidget);
    expect(find.text('Silent auto-label'), findsOneWidget);
  });
}

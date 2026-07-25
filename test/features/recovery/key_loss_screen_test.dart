import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/app.dart';
import 'package:paisatrack/core/crypto/database_cipher.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/recovery/key_loss_screen.dart';
import 'package:paisatrack/features/settings/app_data_reset_service.dart';

class _FakeResetService implements AppDataResetService {
  int deleteCalls = 0;

  @override
  Future<AppDataResetResult> deleteEverything() async {
    deleteCalls++;
    return const AppDataResetResult(deletedFiles: 1, categoryCount: 5);
  }
}

void main() {
  testWidgets('app routes to KeyLossScreen when DatabaseKeyLostError occurs',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith(
            (ref) => Future.error(
              const DatabaseKeyLostError('Key lost test failure'),
            ),
          ),
        ],
        child: const PaisaTrackApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(KeyLossScreen), findsOneWidget);
    expect(find.text('Encryption Key Unavailable'), findsOneWidget);
    expect(find.byKey(const ValueKey('key_loss_reset_button')), findsOneWidget);
  });

  testWidgets('KeyLossScreen reset button invokes deleteEverything after confirmation',
      (tester) async {
    final fakeReset = _FakeResetService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDataResetServiceProvider.overrideWithValue(fakeReset),
        ],
        child: const MaterialApp(
          home: KeyLossScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('key_loss_reset_button')));
    await tester.pumpAndSettle();

    expect(find.text('Reset local database?'), findsOneWidget);

    await tester.tap(find.text('Reset Data'));
    await tester.pumpAndSettle();

    expect(fakeReset.deleteCalls, 1);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/app.dart';
import 'package:paisatrack/core/crypto/database_cipher.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/recovery/database_error_screen.dart';
import 'package:paisatrack/features/recovery/key_loss_screen.dart';

void main() {
  testWidgets('app routes to KeyLossScreen when DatabaseKeyLostError occurs', (
    tester,
  ) async {
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
    expect(
      find.byKey(const ValueKey('key_loss_restore_button')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('key_loss_reset_button')), findsNothing);
  });

  testWidgets('KeyLossScreen requires a backup passphrase before import', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: KeyLossScreen())),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('recovery_passphrase_field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('key_loss_restore_button')),
      findsOneWidget,
    );
    expect(find.text('Reset Data'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('key_loss_restore_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter the backup passphrase to continue.'),
      findsOneWidget,
    );
  });

  testWidgets('app routes to DatabaseErrorScreen on generic database error', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith(
            (ref) => Future.error(
              Exception('Generic database initialization error'),
            ),
          ),
        ],
        child: const PaisaTrackApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DatabaseErrorScreen), findsOneWidget);
    expect(find.byType(KeyLossScreen), findsNothing);
  });
}

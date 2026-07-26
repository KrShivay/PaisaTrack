import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/app.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/core/crypto/database_cipher.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/recovery/key_loss_screen.dart';

void main() {
  group('App startup error routing', () {
    testWidgets('DatabaseKeyLostError routes to KeyLossScreen', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith(
              (ref) => Future.error(
                const DatabaseKeyLostError('key lost'),
              ),
            ),
            smsPermissionControllerProvider.overrideWith(
              () => _FakeSmsController(SmsPermissionStatus.granted),
            ),
          ],
          child: const MaterialApp(home: PaisaTrackApp()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(KeyLossScreen), findsOneWidget);
    });

    testWidgets('Generic error routes to DatabaseErrorScreen with retry',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith(
              (ref) => Future.error(
                StateError('transient I/O failure'),
              ),
            ),
            smsPermissionControllerProvider.overrideWith(
              () => _FakeSmsController(SmsPermissionStatus.granted),
            ),
          ],
          child: const MaterialApp(home: PaisaTrackApp()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Should NOT show KeyLossScreen for non-key errors
      expect(find.byType(KeyLossScreen), findsNothing);
      // Should show retry option
      expect(find.textContaining('Retry'), findsOneWidget);
    });
  });
}

class _FakeSmsController extends AsyncNotifier<SmsPermissionStatus>
    implements SmsPermissionController {
  _FakeSmsController(this._status);
  final SmsPermissionStatus _status;

  @override
  Future<SmsPermissionStatus> build() => Future.value(_status);

  @override
  Future<void> request() async {}

  @override
  Future<void> openSettings() async {}

  @override
  Future<void> recheckStatus() async {}
}

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paisatrack/app.dart';
import 'package:paisatrack/capture/captured_sms_source.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';

import 'support/fake_sms_permission_gate.dart';
import 'support/fake_captured_sms_source.dart';

void main() {
  testWidgets('renders the app shell', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          smsPermissionGateProvider.overrideWithValue(
            FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
          ),
          capturedSmsSourceProvider
              .overrideWithValue(const FakeCapturedSmsSource()),
        ],
        child: const PaisaTrackApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PaisaTrack'), findsOneWidget);
  });

  testWidgets('boots with an in-memory app database override', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          smsPermissionGateProvider.overrideWithValue(
            FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
          ),
          capturedSmsSourceProvider
              .overrideWithValue(const FakeCapturedSmsSource()),
          appDatabaseProvider.overrideWith((ref) async => database),
        ],
        child: const PaisaTrackApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PaisaTrack'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.text('PaisaTrack')),
      listen: false,
    );
    expect(await container.read(appDatabaseProvider.future), same(database));
  });
}

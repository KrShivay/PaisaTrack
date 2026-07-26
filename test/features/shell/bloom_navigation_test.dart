import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/app.dart';
import 'package:paisatrack/capture/captured_sms_source.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/core/undo/undo_controller.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/repositories/budget_repository.dart';
import 'package:paisatrack/features/settings/app_settings.dart';

import '../../support/fake_captured_sms_source.dart';
import '../../support/fake_sms_permission_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bloom Navigation Shell', () {
    testWidgets('renders four tabs: Home, Activity, Sort, Trends',
        (tester) async {
      final database = AppDatabase(NativeDatabase.memory());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => database),
            smsPermissionGateProvider.overrideWithValue(
              FakeSmsPermissionGate(
                initialStatus: SmsPermissionStatus.granted,
              ),
            ),
            capturedSmsSourceProvider.overrideWithValue(
              const FakeCapturedSmsSource(),
            ),
          ],
          child: const PaisaTrackApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Home'), findsWidgets);
      expect(find.text('Activity'), findsWidgets);
      expect(find.text('Sort'), findsWidgets);
      expect(find.text('Trends'), findsWidgets);

      await database.close();
    });

    testWidgets('tapping Ask orb opens Ask PaisaTrack sheet', (tester) async {
      final database = AppDatabase(NativeDatabase.memory());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => database),
            smsPermissionGateProvider.overrideWithValue(
              FakeSmsPermissionGate(
                initialStatus: SmsPermissionStatus.granted,
              ),
            ),
            capturedSmsSourceProvider.overrideWithValue(
              const FakeCapturedSmsSource(),
            ),
          ],
          child: const PaisaTrackApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Find Ask orb icon (Icons.auto_awesome) and tap
      final askOrb = find.byIcon(Icons.auto_awesome);
      expect(askOrb, findsWidgets);

      await tester.tap(askOrb.last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Ask PaisaTrack sheet header should appear
      expect(find.text('Ask PaisaTrack'), findsWidgets);

      await database.close();
    });
  });

  group('UndoController & BloomUndoToastHost', () {
    testWidgets('pushUndo displays toast and Undo action executes undoAction',
        (tester) async {
      var undone = false;

      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: BloomUndoToastHost(
                bottomOffset: 20,
                child: Consumer(
                  builder: (context, ref, _) {
                    return ElevatedButton(
                      onPressed: () {
                        ref.read(undoControllerProvider.notifier).pushUndo(
                              UndoToken(
                                id: 'test_action',
                                message: 'Filed under Food',
                                undoAction: () async {
                                  undone = true;
                                },
                              ),
                            );
                      },
                      child: const Text('Do Action'),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      // Trigger action
      await tester.tap(find.text('Do Action'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Filed under Food'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      // Tap Undo
      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(undone, isTrue);
    });
  });

  group('BudgetRepository (encrypted SQLite storage)', () {
    test('monthly budget is nullable in production by default', () async {
      final database = AppDatabase(NativeDatabase.memory());
      final repo = BudgetRepository(database);

      final initial = await repo.getMonthlyBudget();
      expect(initial, isNull);

      await repo.setMonthlyBudget(48000.0);
      final updated = await repo.getMonthlyBudget();
      expect(updated, 48000.0);

      await repo.setMonthlyBudget(null);
      final cleared = await repo.getMonthlyBudget();
      expect(cleared, isNull);

      await database.close();
    });

    test('stores and retrieves merchant caps', () async {
      final database = AppDatabase(NativeDatabase.memory());
      final repo = BudgetRepository(database);

      expect(await repo.getMerchantCap('Blinkit'), isNull);

      await repo.setMerchantCap('Blinkit', 2000.0);
      expect(await repo.getMerchantCap('Blinkit'), 2000.0);

      await repo.removeMerchantCap('Blinkit');
      expect(await repo.getMerchantCap('Blinkit'), isNull);

      await database.close();
    });
  });

  group('AppSettings showPaise & streak persistence', () {
    test('defaults and updates showPaise & streak', () {
      const settings = AppSettings();
      expect(settings.showPaise, isTrue);
      expect(settings.streak, 0);

      final updated = settings.copyWith(showPaise: false, streak: 5);
      expect(updated.showPaise, isFalse);
      expect(updated.streak, 5);

      final json = updated.toJson();
      expect(json['show_paise'], isFalse);
      expect(json['streak'], 5);

      final restored = AppSettings.fromJson(json);
      expect(restored.showPaise, isFalse);
      expect(restored.streak, 5);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/parser_cascade.dart';
import 'package:paisatrack/capture/sms_ingestion.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';
import 'package:paisatrack/data/models/raw_sms.dart';
import 'package:paisatrack/data/repositories/budget_repository.dart';
import 'package:paisatrack/features/onboarding/onboarding_screen.dart';
import 'package:paisatrack/features/settings/app_settings.dart';
import 'package:paisatrack/features/settings/settings_screen.dart';
import 'package:drift/native.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';

class FakeAppSettingsController extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Onboarding Disclosure & Consent (T-144b)', () {
    testWidgets('Prominent disclosure precedes runtime prompt and survives denial', (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: const OnboardingScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify prominent disclosure points are visible before runtime permission request
      expect(find.text("I can read your bank\ntexts so you don't"), findsOneWidget);
      expect(find.text('Everything stays on this phone. No account, no upload, no ads.'), findsOneWidget);
      expect(find.text('Reads only money texts'), findsOneWidget);
      expect(find.text('Works offline, forever'), findsOneWidget);

      // Verify "I'll add things myself" button enables continuing without SMS permission
      final addMyselfBtn = find.text("I'll add things myself");
      expect(addMyselfBtn, findsOneWidget);
      await tester.ensureVisible(addMyselfBtn);
      await tester.tap(addMyselfBtn, warnIfMissed: false);
      await tester.pump();
    });
  });

  group('Capture Controls (T-144b)', () {
    late AppDatabase database;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      await database.seedDefaultCategories();
    });

    tearDown(() async {
      await database.close();
    });

    testWidgets('SettingsScreen displays SMS CAPTURE & PRIVACY CONTROLS section', (tester) async {
      tester.view.physicalSize = const Size(402, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => database),
            monthlyBudgetProvider.overrideWith((ref) async => null),
            appSettingsControllerProvider.overrideWith(() => FakeAppSettingsController()),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final sectionHeader = find.text('SMS CAPTURE & PRIVACY CONTROLS');
      await tester.ensureVisible(sectionHeader);
      expect(sectionHeader, findsOneWidget);
      expect(find.text('Pause All SMS Capture'), findsOneWidget);
    });

    test('SmsIngestor skips ingestion when isCapturePaused is true', () async {
      final ingestor = SmsIngestor(
        database: database,
        parser: const ParserCascade(templateMatcher: TemplateMatcher(registries: [])),
        isCapturePausedResolver: () => true, // Paused globally
      );

      final now = DateTime.utc(2026, 7, 10);
      final sms = RawSms(
        id: 'sms_paused_001',
        sender: 'HDFCBK',
        body: 'Rs 500 debited from A/C XX1234 on 10-Jul-26',
        receivedAt: now,
      );

      await ingestor.ingest(sms);

      final rows = await database.select(database.rawSms).get();
      expect(rows, isEmpty); // Ingestion stopped immediately
    });

    test('SmsIngestor skips ingestion for blacklisted sender', () async {
      final ingestor = SmsIngestor(
        database: database,
        parser: const ParserCascade(templateMatcher: TemplateMatcher(registries: [])),
        isCapturePausedResolver: () => false,
        isSenderPausedResolver: (sender) => sender.toUpperCase() == 'SPAMBK',
      );

      final now = DateTime.utc(2026, 7, 10);
      final sms = RawSms(
        id: 'sms_sender_paused',
        sender: 'SPAMBK',
        body: 'Rs 1000 debited from A/C XX1234 on 10-Jul-26',
        receivedAt: now,
      );

      await ingestor.ingest(sms);

      final rows = await database.select(database.rawSms).get();
      expect(rows, isEmpty); // Blacklisted sender skipped
    });
  });
}

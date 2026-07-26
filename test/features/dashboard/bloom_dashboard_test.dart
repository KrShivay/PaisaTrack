import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/dashboard/dashboard_screen.dart';
import 'package:paisatrack/features/dashboard/dashboard_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpDashboard(WidgetTester tester, AppDatabase database) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
        ],
        child: const MaterialApp(
          home: BloomUndoToastHost(
            child: DashboardScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('Bloom DashboardScreen', () {
    testWidgets('renders greeting, mascot, and streak chip', (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      await pumpDashboard(tester, database);

      expect(find.textContaining('Good '), findsOneWidget);
      expect(find.textContaining('streak'), findsOneWidget);
      expect(find.byType(BloomMascot), findsOneWidget);

      await database.close();
    });

    testWidgets('renders Hero Ring and metric switcher pills', (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      await pumpDashboard(tester, database);

      expect(find.byType(BloomHeroRing), findsOneWidget);
      expect(find.text('Safe today'), findsOneWidget);
      expect(find.text('Net flow'), findsOneWidget);
      expect(find.text('Burn'), findsOneWidget);
      expect(find.text('Runway'), findsOneWidget);

      await database.close();
    });

    testWidgets('tapping metric switcher pill changes selected metric',
        (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      await pumpDashboard(tester, database);

      // Tap Net flow
      await tester.tap(find.text('Net flow'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('NET FLOW'), findsOneWidget);

      // Tap Burn
      await tester.tap(find.text('Burn'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('BURN RATE'), findsOneWidget);

      await database.close();
    });

    testWidgets('insight card renders nothing when no insights exist',
        (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      await pumpDashboard(tester, database);

      // No fabricated insight strings
      expect(find.textContaining('Blinkit'), findsNothing);
      expect(find.text('Sure'), findsNothing);
      expect(find.textContaining('Cap set'), findsNothing);

      await database.close();
    });
  });
}

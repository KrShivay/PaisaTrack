import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/bloom/bloom_bottom_inset.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';
import 'package:paisatrack/features/insights/insights_screen.dart';
import 'package:paisatrack/features/settings/app_settings.dart';
import 'package:paisatrack/features/settings/settings_screen.dart';

const _navigationKey = ValueKey('floating_navigation_pill');

class _TestAppSettingsController extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

Widget _underFloatingNavigation(Widget child) {
  return MaterialApp(
    builder: (context, routedChild) {
      final deviceMediaQuery = MediaQuery.of(context);
      return MediaQuery(
        data: BloomBottomInset.forTabContent(deviceMediaQuery),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (routedChild != null) routedChild,
            Positioned(
              left: 20,
              right: 20,
              bottom: deviceMediaQuery.padding.bottom + kBottomNavBottomGap,
              child: Container(
                key: _navigationKey,
                height: kBottomNavHeight,
              ),
            ),
          ],
        ),
      );
    },
    home: child,
  );
}

void _setViewport(WidgetTester tester, {required double systemBottomInset}) {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  tester.view.viewPadding = FakeViewPadding(bottom: systemBottomInset);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewPadding();
    tester.view.resetViewInsets();
  });
}

void _expectAboveNavigation(WidgetTester tester, Finder target) {
  expect(
    tester.getRect(target).bottom,
    lessThanOrEqualTo(tester.getRect(find.byKey(_navigationKey)).top),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final inset in [24.0, 48.0]) {
    final navigationMode = inset == 24 ? 'gesture' : 'three-button';
    testWidgets('Trends last section clears $navigationMode navigation',
        (tester) async {
      _setViewport(tester, systemBottomInset: inset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardAggregateProvider.overrideWith(
              (ref) async => _emptyDashboardAggregate,
            ),
          ],
          child: _underFloatingNavigation(const InsightsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final finalSection = find.text('No merchant data for this period');
      await tester.drag(find.byType(ListView).first, const Offset(0, -5000));
      await tester.pump(const Duration(milliseconds: 200));
      expect(finalSection, findsOneWidget);
      _expectAboveNavigation(tester, finalSection);
    });

    testWidgets('Settings final action clears $navigationMode navigation',
        (tester) async {
      _setViewport(tester, systemBottomInset: inset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSettingsControllerProvider
                .overrideWith(() => _TestAppSettingsController()),
          ],
          child: _underFloatingNavigation(const SettingsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final finalAction = find.text('Delete all local data');
      await tester.drag(find.byType(ListView).first, const Offset(0, -5000));
      await tester.pump(const Duration(milliseconds: 200));
      expect(finalAction, findsOneWidget);
      _expectAboveNavigation(tester, finalAction);
    });
  }
}

const _emptyDashboardAggregate = DashboardAggregateSnapshot(
  debitTotal: 0,
  creditTotal: 0,
  previousSpend: 0,
  categories: [],
  merchants: [],
  trendByMonth: {},
);

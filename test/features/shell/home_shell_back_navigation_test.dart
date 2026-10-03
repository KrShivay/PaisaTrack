import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';
import 'package:paisatrack/features/home/home_shell.dart';

const _tabIcons = [
  Icons.home_outlined,
  Icons.receipt_long_outlined,
  Icons.fact_check_outlined,
  Icons.insights_outlined,
];
const _selectedTabIcons = [
  Icons.home_rounded,
  Icons.receipt_long_rounded,
  Icons.fact_check_rounded,
  Icons.insights_rounded,
];

Future<void> _pumpShell(
  WidgetTester tester, {
  Size? size,
  double bottomInset = 0,
  double textScale = 1,
  ThemeData? theme,
}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(bottom: bottomInset);
    tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
      tester.view.resetViewPadding();
    });
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith(
          (ref) => Completer<AppDatabase>().future,
        ),
      ],
      child: MaterialApp(
        theme: theme,
        home: const HomeShell(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
}

Future<dynamic> _sendPredictiveBackMessage(
  WidgetTester tester,
  String method, [
  Map<String, Object?>? arguments,
]) async {
  final message = const StandardMethodCodec().encodeMethodCall(
    MethodCall(method, arguments),
  );
  final response =
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.backGesture.name,
    message,
    (_) {},
  );
  return response == null
      ? null
      : const StandardMethodCodec().decodeEnvelope(response);
}

class _SystemPopTracker {
  _SystemPopTracker(WidgetTester tester) {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') calls++;
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
  }

  int calls = 0;
}

class _FrameworkBackTracker {
  _FrameworkBackTracker(WidgetTester tester) {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
        current = call.arguments! as bool;
        values.add(current!);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
  }

  final List<bool> values = [];
  bool? current;
}

class _CustomAndroidTransitionsBuilder
    extends FadeForwardsPageTransitionsBuilder {
  const _CustomAndroidTransitionsBuilder();
}

_SystemPopTracker _trackSystemPop(WidgetTester tester) =>
    _SystemPopTracker(tester);

NavigatorState _navigator(WidgetTester tester, int index) => tester.state(
      find.descendant(
        of: find.byKey(
          ValueKey<String>('home_tab_page_$index'),
          skipOffstage: false,
        ),
        matching: find.byType(Navigator, skipOffstage: false),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'retained child navigators cannot release native back ownership',
    (tester) async {
      final frameworkBack = _FrameworkBackTracker(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _pumpShell(tester);
      await tester.pump();

      expect(frameworkBack.values, isNotEmpty);
      expect(frameworkBack.values.last, isTrue);
      frameworkBack.values.clear();

      for (var index = 1; index < _tabIcons.length; index++) {
        await tester.tap(find.byIcon(_tabIcons[index]));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        expect(frameworkBack.current, isTrue);
      }

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(frameworkBack.current, isTrue);
      expect(frameworkBack.values, everyElement(isTrue));

      await tester.tap(find.byIcon(_tabIcons[0]));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('nested routes pop one at a time and honor route vetoes',
      (tester) async {
    await _pumpShell(tester);
    final home = _navigator(tester, 0);
    home.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Home detail one')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final vetoRoute = MaterialPageRoute<void>(
      builder: (_) => const PopScope(
        canPop: false,
        child: Scaffold(body: Text('Home detail two')),
      ),
    );
    home.push<void>(vetoRoute);
    await tester.pump(const Duration(milliseconds: 300));

    await _back(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Home detail two'), findsOneWidget);

    // After removing the route veto, each accepted back reveals exactly one
    // previously visited route.
    home.removeRoute(vetoRoute);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Home detail one'), findsOneWidget);
    await _back(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(home.canPop(), isFalse);
  });

  testWidgets('overlapping back waits for an async route decision',
      (tester) async {
    final systemPop = _trackSystemPop(tester);
    await _pumpShell(tester);
    final decision = Completer<bool>();
    _navigator(tester, 0).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            // ignore: deprecated_member_use
            WillPopScope(
          // Async confirmation is intentional here; verify a second system back
          // cannot escape while the first Navigator.maybePop is still pending.
          onWillPop: () => decision.future,
          child: const Scaffold(body: Text('Awaiting route decision')),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await _back(tester);
    await _back(tester);
    expect(find.text('Awaiting route decision'), findsOneWidget);
    expect(find.text('Press back again to exit'), findsNothing);
    expect(systemPop.calls, 0);
    decision.complete(false);
    await tester.pump();
    await tester.pump();
    expect(find.text('Awaiting route decision'), findsOneWidget);
    expect(find.text('Press back again to exit'), findsNothing);
    expect(systemPop.calls, 0);
  });

  testWidgets('all tab stacks survive nonadjacent switches and root falls Home',
      (tester) async {
    await _pumpShell(tester);
    for (var index = 0; index < 4; index++) {
      _navigator(tester, index).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(body: Text('tab detail $index')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(_tabIcons[(index + 1) % 4]));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(_selectedTabIcons[(index + 1) % 4]), findsOneWidget);
      expect(
        TickerMode.valuesOf(
          tester.element(
            find.text('tab detail $index', skipOffstage: false),
          ),
        ).enabled,
        isFalse,
      );
    }

    expect(find.text('tab detail 0', skipOffstage: false), findsOneWidget);
    for (var index = 0; index < 4; index++) {
      expect(_navigator(tester, index).canPop(), isTrue);
    }
    await _back(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_navigator(tester, 0).canPop(), isFalse);

    await tester.tap(find.byIcon(Icons.insights_outlined));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await _back(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('tab detail 3', skipOffstage: false), findsOneWidget);
    await _back(tester);
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(TickerMode.valuesOf(_navigator(tester, 0).context).enabled, isTrue);
  });

  testWidgets('inactive tabs preserve custom Android transition builders',
      (tester) async {
    const customBuilder = _CustomAndroidTransitionsBuilder();
    await _pumpShell(
      tester,
      theme: ThemeData(
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {TargetPlatform.android: customBuilder},
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    final activityNavigator = _navigator(tester, 1);
    activityNavigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Custom themed detail')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      Theme.of(
        tester.element(
          find.text('Custom themed detail', skipOffstage: false),
        ),
      ).pageTransitionsTheme.builders[TargetPlatform.android],
      same(customBuilder),
    );
  });

  testWidgets('Activity Sort and Trends roots return Home without exiting',
      (tester) async {
    final systemPop = _trackSystemPop(tester);
    await _pumpShell(tester);

    for (var index = 1; index < 4; index++) {
      await tester.tap(find.byIcon(_tabIcons[index]));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(_selectedTabIcons[index]), findsOneWidget);
      await _back(tester);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
      expect(systemPop.calls, 0);
    }
  });

  testWidgets('reselecting the active tab preserves its existing root reset',
      (tester) async {
    await _pumpShell(tester);
    final home = _navigator(tester, 0);
    home.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Reselect detail')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(home.canPop(), isTrue);

    await tester.tap(find.byIcon(Icons.home_rounded));
    await tester.pump(const Duration(milliseconds: 300));
    expect(home.canPop(), isFalse);
  });

  testWidgets('back keeps programmatic tab requests in sync', (tester) async {
    await _pumpShell(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeShell)),
    );
    container.read(homeTabControllerProvider.notifier).state = 1;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.receipt_long_rounded), findsOneWidget);

    await _back(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(container.read(homeTabControllerProvider), 0);

    container.read(homeTabControllerProvider.notifier).state = 1;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.receipt_long_rounded), findsOneWidget);
  });

  testWidgets(
      'Home root asks twice and exits only inside the two-second window',
      (tester) async {
    final systemPop = _trackSystemPop(tester);
    await _pumpShell(tester);

    await _back(tester);
    expect(find.text('Press back again to exit'), findsOneWidget);
    expect(systemPop.calls, 0);
    await tester.pump(const Duration(milliseconds: 1999));
    await _back(tester);
    expect(systemPop.calls, 1);
  });

  testWidgets('a root sheet dismiss clears an armed Home exit', (tester) async {
    final systemPop = _trackSystemPop(tester);
    await _pumpShell(tester);
    await _back(tester);
    expect(find.text('Press back again to exit'), findsOneWidget);

    final rootNavigator = Navigator.of(tester.element(find.byType(HomeShell)));
    rootNavigator.push<void>(
      DialogRoute<void>(
        context: tester.element(find.byType(HomeShell)),
        builder: (_) =>
            const AlertDialog(content: Text('Transient root sheet')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _back(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Transient root sheet'), findsNothing);

    await _back(tester);
    expect(find.text('Press back again to exit'), findsOneWidget);
    expect(systemPop.calls, 0);
    await _back(tester);
    expect(systemPop.calls, 1);
  });

  testWidgets('exit prompt replaces queued notice and clears the floating pill',
      (tester) async {
    for (final bottomInset in [24.0, 48.0]) {
      await _pumpShell(
        tester,
        size: const Size(402, 874),
        bottomInset: bottomInset,
        textScale: 2,
      );
      final messenger = tester.state<ScaffoldMessengerState>(
        find.descendant(
          of: find.byType(HomeShell),
          matching: find.byType(ScaffoldMessenger),
        ),
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('An earlier notice'),
          duration: Duration(seconds: 10),
        ),
      );
      await tester.pump();

      await _back(tester);
      expect(find.text('An earlier notice'), findsNothing);
      expect(find.text('Press back again to exit'), findsOneWidget);
      final prompt = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('home-exit-snackbar')),
          matching: find.byType(Material),
        ),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-exit-snackbar')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.liveRegion == true,
          ),
        ),
        findsWidgets,
      );
      final pill = tester.getRect(
        find.byKey(
          const ValueKey('floating_navigation_pill'),
        ),
      );
      expect(prompt.bottom, lessThanOrEqualTo(pill.top));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('an unrelated shell rebuild preserves the exit confirmation',
      (tester) async {
    final systemPop = _trackSystemPop(tester);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await _pumpShell(tester);

    await _back(tester);
    expect(find.text('Press back again to exit'), findsOneWidget);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();
    expect(find.text('Press back again to exit'), findsOneWidget);
    await _back(tester);
    expect(systemPop.calls, 1);
  });

  testWidgets('a back exactly at timeout expiry rearms instead of exiting',
      (tester) async {
    final systemPop = _trackSystemPop(tester);
    await _pumpShell(tester);

    await _back(tester);
    await tester.pump(const Duration(seconds: 2));
    await _back(tester);
    expect(systemPop.calls, 0);
    await _back(tester);
    expect(systemPop.calls, 1);
  });

  testWidgets('IME visibility and app background clear the exit prompt',
      (tester) async {
    final systemPop = _trackSystemPop(tester);
    addTearDown(() => tester.view.viewInsets = FakeViewPadding.zero);
    await _pumpShell(tester);
    await _back(tester);
    expect(find.text('Press back again to exit'), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pump();
    expect(find.text('Press back again to exit'), findsNothing);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();

    await _back(tester);
    expect(find.text('Press back again to exit'), findsOneWidget);
    expect(systemPop.calls, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('Press back again to exit'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    await _back(tester);
    expect(find.text('Press back again to exit'), findsOneWidget);
    expect(systemPop.calls, 0);
    await _back(tester);
    expect(systemPop.calls, 1);
  });

  testWidgets(
    'canceled predictive back preserves an armed Home exit',
    (tester) async {
      final systemPop = _trackSystemPop(tester);
      await _pumpShell(tester);
      await _back(tester);
      expect(find.text('Press back again to exit'), findsOneWidget);

      expect(
        await _sendPredictiveBackMessage(tester, 'startBackGesture', {
          'touchOffset': <double>[5, 300],
          'progress': 0.0,
          'swipeEdge': 0,
        }),
        isFalse,
      );
      await _sendPredictiveBackMessage(tester, 'cancelBackGesture');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Press back again to exit'), findsOneWidget);

      await _back(tester);
      expect(systemPop.calls, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('Home never pops an enclosing route', (tester) async {
    final systemPop = _trackSystemPop(tester);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith(
          (ref) => Completer<AppDatabase>().future,
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const HomeShell(),
                  ),
                ),
                child: const Text('Open Home'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open Home'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    await _back(tester);
    expect(find.text('Press back again to exit'), findsOneWidget);
    await _back(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(systemPop.calls, 1);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.text('Open Home'), findsNothing);
  });

  testWidgets('PageView swipes retain the selected tab route stack',
      (tester) async {
    await _pumpShell(tester);
    final home = _navigator(tester, 0);
    home.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Swipe-retained detail')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.drag(find.byType(PageView).first, const Offset(-500, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.receipt_long_rounded), findsOneWidget);
    await tester.drag(find.byType(PageView).first, const Offset(500, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Swipe-retained detail'), findsOneWidget);
    expect(home.canPop(), isTrue);
  });

  testWidgets(
    'predictive back affects only the active uncovered tab and respects cancel',
    (tester) async {
      await _pumpShell(tester);

      await tester.tap(find.byIcon(Icons.receipt_long_outlined));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      final activity = _navigator(tester, 1);
      activity.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Activity detail')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.byIcon(Icons.home_outlined));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      final home = _navigator(tester, 0);
      home.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Home detail')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        ModalRoute.of(tester.element(find.text('Home detail')))
            ?.popGestureEnabled,
        isTrue,
      );
      expect(
        Theme.of(tester.element(find.text('Home detail')))
            .pageTransitionsTheme
            .builders[TargetPlatform.android],
        isA<PredictiveBackPageTransitionsBuilder>(),
      );

      final gesture = <String, Object?>{
        'touchOffset': <double>[5, 300],
        'progress': 0.0,
        'swipeEdge': 0,
      };
      expect(
        await _sendPredictiveBackMessage(
          tester,
          'startBackGesture',
          gesture,
        ),
        isTrue,
      );
      await _sendPredictiveBackMessage(tester, 'cancelBackGesture');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Home detail'), findsOneWidget);
      expect(find.text('Activity detail', skipOffstage: false), findsOneWidget);
      expect(find.text('Press back again to exit'), findsNothing);

      expect(
        await _sendPredictiveBackMessage(
          tester,
          'startBackGesture',
          gesture,
        ),
        isTrue,
      );
      final homeDetailRoute = ModalRoute.of(
        tester.element(find.text('Home detail')),
      )!;
      expect(homeDetailRoute.popGestureInProgress, isTrue);
      await _sendPredictiveBackMessage(tester, 'updateBackGestureProgress', {
        'touchOffset': <double>[100, 300],
        'progress': 0.35,
        'swipeEdge': 0,
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(homeDetailRoute.popGestureInProgress, isTrue);
      await _sendPredictiveBackMessage(tester, 'commitBackGesture');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Home detail'), findsNothing);
      expect(find.text('Activity detail', skipOffstage: false), findsOneWidget);
      expect(home.canPop(), isFalse);
      expect(activity.canPop(), isTrue);

      home.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Modal covered detail')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final shellContext = tester.element(find.byType(HomeShell));
      Navigator.of(shellContext).push<void>(
        DialogRoute<void>(
          context: shellContext,
          builder: (_) =>
              const AlertDialog(content: Text('Blocking root dialog')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        await _sendPredictiveBackMessage(
          tester,
          'startBackGesture',
          gesture,
        ),
        isFalse,
      );
      await _sendPredictiveBackMessage(tester, 'updateBackGestureProgress', {
        'touchOffset': <double>[100, 300],
        'progress': 0.35,
        'swipeEdge': 0,
      });
      await tester.pump(const Duration(milliseconds: 300));
      await _sendPredictiveBackMessage(tester, 'commitBackGesture');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Blocking root dialog'), findsNothing);
      expect(
        find.text('Modal covered detail', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('Activity detail', skipOffstage: false), findsOneWidget);
      expect(find.text('Press back again to exit'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

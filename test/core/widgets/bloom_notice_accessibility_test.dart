import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/bloom/bloom_notice.dart';

void main() {
  testWidgets('notice action is a named 48dp button and works at its edge',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var semanticsDisposed = false;
    addTearDown(() {
      if (!semanticsDisposed) semantics.dispose();
    });
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: BloomNotice.warning(
            message: 'Some transactions need review.',
            actionLabel: 'Review now',
            onAction: () => calls++,
          ),
        ),
      ),
    );

    final action = find.bySemanticsLabel('Review now');
    final data = tester.getSemantics(action).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isEnabled.toBoolOrNull(), isTrue);
    expect(tester.getSemantics(action).rect.height, greaterThanOrEqualTo(48));
    expect(tester.getSemantics(action).rect.width, greaterThanOrEqualTo(48));
    final rect = tester.getRect(action);
    expect(rect.height, greaterThanOrEqualTo(48));
    expect(rect.width, greaterThanOrEqualTo(48));
    await tester.tapAt(Offset(rect.right - 1, rect.bottom - 1));
    expect(calls, 1);
    semantics.dispose();
    semanticsDisposed = true;
  });

  testWidgets('notice action without callback is announced disabled',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var semanticsDisposed = false;
    addTearDown(() {
      if (!semanticsDisposed) semantics.dispose();
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BloomNotice.error(
            message: 'Could not retry now.',
            actionLabel: 'Retry',
          ),
        ),
      ),
    );

    final action = find.bySemanticsLabel('Retry');
    final data = tester.getSemantics(action).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isEnabled.toBoolOrNull(), isNotNull);
    expect(data.flagsCollection.isEnabled.toBoolOrNull(), isFalse);
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    expect(tester.getRect(action).height, greaterThanOrEqualTo(48));
    expect(tester.getRect(action).width, greaterThanOrEqualTo(48));
    semantics.dispose();
    semanticsDisposed = true;
  });
}

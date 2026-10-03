import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';

/// Pumps a few short frames so Drift stream updates reach the widgets.
Future<void> pumpDriftFrames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Unmounts the tree and closes an in-memory database inside the test.
///
/// Drift's stream-query store schedules a `Timer.run` when the last watcher
/// cancels; pumping frames around `close()` lets it run under fake async
/// instead of leaving it pending for flutter_test teardown.
Future<void> unmountAndCloseDatabase(
  WidgetTester tester,
  AppDatabase database,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await pumpDriftFrames(tester);
  final closing = database.close();
  await pumpDriftFrames(tester);
  await closing;
}

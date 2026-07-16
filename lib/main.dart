import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'intelligence/nightly_job.dart';

/// Application entry point.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: PaisaTrackApp(),
    ),
  );
  // Platform scheduling is non-essential startup work. Register it after the
  // first frame so a slow plugin/device service cannot hold the launch screen.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initializeNightlyWorkSafely());
  });
}

Future<void> _initializeNightlyWorkSafely() async {
  try {
    await initializeNightlyWork();
  } on Object {
    // WorkManager registration is best-effort; the in-app experience remains
    // available and registration is retried on the next launch.
  }
}

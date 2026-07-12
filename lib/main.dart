import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'intelligence/nightly_job.dart';

/// Application entry point.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeNightlyWork();
  runApp(
    const ProviderScope(
      child: PaisaTrackApp(),
    ),
  );
}

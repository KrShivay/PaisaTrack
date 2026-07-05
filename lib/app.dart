import 'package:flutter/material.dart';

/// Root widget for the PaisaTrack Flutter application.
///
/// App-wide providers, navigation, and theme configuration should be attached
/// here so tests can boot the same shell that production uses.
class PaisaTrackApp extends StatelessWidget {
  const PaisaTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PaisaTrack',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Text('PaisaTrack'),
        ),
      ),
    );
  }
}

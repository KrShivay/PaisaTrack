import 'package:flutter/material.dart';

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

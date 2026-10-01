import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Injectable source of wall-clock time for UI and provider calculations.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

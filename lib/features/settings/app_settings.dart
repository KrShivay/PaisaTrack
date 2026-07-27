import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants.dart';

enum AppThemeChoice {
  dark,
  light,
  system;

  ThemeMode get themeMode {
    return switch (this) {
      AppThemeChoice.dark => ThemeMode.dark,
      AppThemeChoice.light => ThemeMode.light,
      AppThemeChoice.system => ThemeMode.system,
    };
  }

  String get label {
    return switch (this) {
      AppThemeChoice.dark => 'Dark',
      AppThemeChoice.light => 'Light',
      AppThemeChoice.system => 'System',
    };
  }
}

class AppSettings {
  const AppSettings({
    this.themeChoice = AppThemeChoice.dark,
    this.askDailyBudget = AppConstants.askNowDailyBudget,
    this.showPaise = true,
    this.streak = 0,
    this.isCapturePaused = false,
    this.pausedSenders = const [],
  });

  final AppThemeChoice themeChoice;
  final int askDailyBudget;
  final bool showPaise;
  final int streak;
  final bool isCapturePaused;
  final List<String> pausedSenders;

  AppSettings copyWith({
    AppThemeChoice? themeChoice,
    int? askDailyBudget,
    bool? showPaise,
    int? streak,
    bool? isCapturePaused,
    List<String>? pausedSenders,
  }) {
    return AppSettings(
      themeChoice: themeChoice ?? this.themeChoice,
      askDailyBudget: askDailyBudget ?? this.askDailyBudget,
      showPaise: showPaise ?? this.showPaise,
      streak: streak ?? this.streak,
      isCapturePaused: isCapturePaused ?? this.isCapturePaused,
      pausedSenders: pausedSenders ?? this.pausedSenders,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'theme_choice': themeChoice.name,
      'ask_daily_budget': askDailyBudget,
      'show_paise': showPaise,
      'streak': streak,
      'is_capture_paused': isCapturePaused,
      'paused_senders': pausedSenders,
    };
  }

  static AppSettings fromJson(Map<String, Object?> json) {
    return AppSettings(
      themeChoice: AppThemeChoice.values.byName(
        json['theme_choice'] as String? ?? AppThemeChoice.dark.name,
      ),
      askDailyBudget:
          json['ask_daily_budget'] as int? ?? AppConstants.askNowDailyBudget,
      showPaise: json['show_paise'] as bool? ?? true,
      streak: json['streak'] as int? ?? 0,
      isCapturePaused: json['is_capture_paused'] as bool? ?? false,
      pausedSenders: (json['paused_senders'] as List?)
              ?.cast<String>()
              .toList() ??
          const [],
    );
  }
}

class AppSettingsStore {
  const AppSettingsStore(this._directory);

  final Directory _directory;

  File get _file => File(p.join(_directory.path, 'settings.json'));

  Future<AppSettings> read() async {
    final file = _file;
    if (!await file.exists()) return const AppSettings();

    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, Object?>;
    return AppSettings.fromJson(decoded);
  }

  Future<void> write(AppSettings settings) async {
    await _directory.create(recursive: true);
    await _file.writeAsString(jsonEncode(settings.toJson()), flush: true);
  }

  Future<void> clear() async {
    final file = _file;
    if (await file.exists()) {
      await file.delete();
    }
  }
}

final settingsDirectoryProvider = FutureProvider<Directory>((ref) {
  return getApplicationDocumentsDirectory();
});

final appSettingsStoreProvider = FutureProvider<AppSettingsStore>((ref) async {
  return AppSettingsStore(await ref.watch(settingsDirectoryProvider.future));
});

final appSettingsControllerProvider =
    AsyncNotifierProvider<AppSettingsController, AppSettings>(
  AppSettingsController.new,
);

class AppSettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    try {
      return await (await _store()).read();
    } on MissingPluginException {
      return const AppSettings();
    } on FileSystemException {
      return const AppSettings();
    } on FormatException {
      return const AppSettings();
    } on ArgumentError {
      return const AppSettings();
    }
  }

  Future<void> setThemeChoice(AppThemeChoice choice) async {
    final next = (state.valueOrNull ?? const AppSettings()).copyWith(
      themeChoice: choice,
    );
    await _save(next);
  }

  Future<void> setAskDailyBudget(int budget) async {
    final next = (state.valueOrNull ?? const AppSettings()).copyWith(
      askDailyBudget: budget,
    );
    await _save(next);
  }

  Future<void> setShowPaise(bool showPaise) async {
    final next = (state.valueOrNull ?? const AppSettings()).copyWith(
      showPaise: showPaise,
    );
    await _save(next);
  }

  Future<void> setStreak(int streak) async {
    final next = (state.valueOrNull ?? const AppSettings()).copyWith(
      streak: streak,
    );
    await _save(next);
  }

  Future<void> setCapturePaused(bool paused) async {
    final next = (state.valueOrNull ?? const AppSettings()).copyWith(
      isCapturePaused: paused,
    );
    await _save(next);
  }

  Future<void> setSenderPaused(String sender, bool paused) async {
    final current = [...(state.valueOrNull?.pausedSenders ?? <String>[])];
    final normalized = sender.trim().toUpperCase();
    if (normalized.isEmpty) return;
    if (paused && !current.contains(normalized)) {
      current.add(normalized);
    } else if (!paused) {
      current.remove(normalized);
    }
    final next = (state.valueOrNull ?? const AppSettings()).copyWith(
      pausedSenders: current,
    );
    await _save(next);
  }

  Future<void> incrementStreak() async {
    final current = state.valueOrNull?.streak ?? 0;
    await setStreak(current + 1);
  }

  Future<void> resetToDefaults() async {
    try {
      await (await _store()).clear();
    } on MissingPluginException {
      // Widget tests can run without path_provider.
    }
    state = const AsyncData(AppSettings());
  }

  Future<void> _save(AppSettings settings) async {
    state = AsyncData(settings);
    try {
      await (await _store()).write(settings);
    } on MissingPluginException {
      // Keep in-memory settings for tests and unsupported hosts.
    }
  }

  Future<AppSettingsStore> _store() async {
    try {
      return await ref.read(appSettingsStoreProvider.future);
    } on MissingPluginException {
      return AppSettingsStore(Directory.systemTemp);
    }
  }
}

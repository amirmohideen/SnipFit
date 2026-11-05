import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_store.dart';

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final raw = ref.read(localStoreProvider).getString(Keys.themeMode);
    return ThemeMode.values.firstWhere((m) => m.name == raw, orElse: () => ThemeMode.system);
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(localStoreProvider).setString(Keys.themeMode, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

/// Null means "follow the system language".
class LocaleController extends Notifier<Locale?> {
  @override
  Locale? build() {
    final raw = ref.read(localStoreProvider).getString(Keys.localeOverride);
    return raw == null || raw.isEmpty ? null : Locale(raw);
  }

  Future<void> set(Locale? locale) async {
    state = locale;
    await ref.read(localStoreProvider).setString(Keys.localeOverride, locale?.languageCode ?? '');
  }
}

final localeProvider = NotifierProvider<LocaleController, Locale?>(LocaleController.new);

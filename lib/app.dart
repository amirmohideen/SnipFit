import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design/theme.dart';
import 'features/settings/preferences.dart';
import 'l10n/l10n.dart';
import 'routing/router.dart';

class SnipfitApp extends ConsumerWidget {
  const SnipfitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final effective = locale ?? PlatformDispatcher.instance.locale;
    return MaterialApp.router(
      title: 'Snipfit',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: SnipTheme.light(effective),
      darkTheme: SnipTheme.dark(effective),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
    );
  }
}

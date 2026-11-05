import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snipfit/core/analytics/analytics.dart';
import 'package:snipfit/core/storage/local_store.dart';
import 'package:snipfit/design/theme.dart';
import 'package:snipfit/l10n/l10n.dart';

/// Records analytics events instead of sending them.
class RecordingAnalytics extends NoopAnalytics {
  final events = <String>[];

  @override
  Future<void> track(String event, [Map<String, Object?>? props]) async => events.add(event);
}

/// Renders on an iPhone-sized surface (390 x 844 logical points).
void usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<({LocalStore store, RecordingAnalytics analytics})> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  List<Override> overrides = const [],
  Locale locale = const Locale('en'),
  Map<String, Object> prefs = const {},
}) async {
  usePhoneSurface(tester);
  SharedPreferences.setMockInitialValues(prefs);
  final store = await LocalStore.open();
  final analytics = RecordingAnalytics();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        analyticsProvider.overrideWithValue(analytics),
        ...overrides,
      ],
      child: MaterialApp(
        theme: SnipTheme.light(locale),
        locale: locale,
        supportedLocales: supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (store: store, analytics: analytics);
}

/// Like [pumpScreen] but inside a GoRouter, with stub pages for the routes
/// the screen navigates to (each shows `route:<location>`).
Future<({LocalStore store, RecordingAnalytics analytics})> pumpRouted(
  WidgetTester tester,
  Widget screen, {
  List<String> stubs = const [],
  List<Override> overrides = const [],
  Map<String, Object> prefs = const {},
}) async {
  usePhoneSurface(tester);
  SharedPreferences.setMockInitialValues(prefs);
  final store = await LocalStore.open();
  final analytics = RecordingAnalytics();
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(path: '/start', builder: (_, _) => screen),
      for (final s in stubs) GoRoute(path: s, builder: (_, state) => Scaffold(body: Text('route:${state.uri}'))),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        analyticsProvider.overrideWithValue(analytics),
        ...overrides,
      ],
      child: MaterialApp.router(
        theme: SnipTheme.light(const Locale('en')),
        supportedLocales: supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (store: store, analytics: analytics);
}

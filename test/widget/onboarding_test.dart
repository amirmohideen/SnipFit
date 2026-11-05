import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snipfit/config/legal_versions.dart';
import 'package:snipfit/core/analytics/analytics_events.dart';
import 'package:snipfit/features/onboarding/onboarding_screens.dart';

import 'harness.dart';

void main() {
  group('Age screen', () {
    testWidgets('neutral picker: nothing preselected, Continue disabled until a year is picked', (tester) async {
      await pumpRouted(tester, const AgeScreen(), stubs: ['/terms']);
      expect(find.text('Select year'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'));
      expect(button.onPressed, isNull);
      // No hint at a required age anywhere on the screen.
      expect(find.textContaining('13'), findsNothing);
      expect(find.textContaining('18'), findsNothing);
    });

    testWidgets('under 13 is blocked with a friendly message', (tester) async {
      final env = await pumpRouted(tester, const AgeScreen(), stubs: ['/terms']);
      await tester.tap(find.text('Select year'));
      await tester.pumpAndSettle();
      final year = DateTime.now().year - 8;
      await tester.scrollUntilVisible(find.text('$year'), 100, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text('$year'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Sorry!'), findsOneWidget);
      expect(env.analytics.events, isNot(contains(AnalyticsEvents.ageConfirmed)));
    });

    testWidgets('an adult continues to the terms', (tester) async {
      final env = await pumpRouted(tester, const AgeScreen(), stubs: ['/terms']);
      await tester.tap(find.text('Select year'));
      await tester.pumpAndSettle();
      final year = DateTime.now().year - 30;
      await tester.scrollUntilVisible(find.text('$year'), 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text('$year'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(find.text('route:/terms'), findsOneWidget);
      expect(env.analytics.events, contains(AnalyticsEvents.ageConfirmed));
      expect(env.store.getBool('age.isAdult'), isTrue);
    });
  });

  group('Terms clickwrap', () {
    testWidgets('three bullets, both links, unticked box, Continue disabled until ticked', (tester) async {
      final env = await pumpRouted(tester, const TermsScreen(), stubs: ['/mode', '/privacy-choices']);
      expect(find.text('Terms of Use'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isFalse);
      Finder continueButton() => find.widgetWithText(FilledButton, 'Continue');
      expect(tester.widget<FilledButton>(continueButton()).onPressed, isNull);

      await tester.ensureVisible(find.byKey(const Key('terms-checkbox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('terms-checkbox')));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(continueButton()).onPressed, isNotNull);

      await tester.tap(continueButton());
      await tester.pumpAndSettle();
      expect(find.textContaining('route:/'), findsOneWidget);
      // The accepted version and timestamp are logged.
      final record = env.store.getJson('consent.terms')!;
      expect(record['version'], ConsentVersions.terms);
      expect(record['accepted'], isTrue);
      expect(DateTime.tryParse(record['at']! as String), isNotNull);
      expect(env.analytics.events, contains(AnalyticsEvents.termsAccepted));
    });
  });

  testWidgets('Camera explainer button says Continue, never Allow', (tester) async {
    await pumpRouted(tester, const CameraIntroScreen(), stubs: ['/']);
    expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
    expect(find.text('Allow'), findsNothing);
    expect(find.text('Skip'), findsOneWidget);
  });

  testWidgets('Biometric consent needs its own unticked checkbox', (tester) async {
    final env = await pumpRouted(tester, const BiometricConsentScreen(next: '/capture'), stubs: ['/capture', '/']);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue')).onPressed, isNull);
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(find.text('route:/capture'), findsOneWidget);
    expect(env.store.getJson('consent.biometric')!['version'], ConsentVersions.biometric);
  });
}

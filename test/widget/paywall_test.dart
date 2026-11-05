import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snipfit/core/analytics/analytics_events.dart';
import 'package:snipfit/features/paywall/paywall_screen.dart';
import 'package:snipfit/features/paywall/purchases_service.dart';

import 'harness.dart';

/// Store-loaded, localized prices (a German storefront, to prove nothing is
/// hardcoded in dollars).
class FakePurchases implements PurchasesService {
  FakePurchases({this.offer});

  final PaywallOffer? offer;
  final purchased = <String>[];

  static const yearly = Plan(
    kind: PlanKind.yearly,
    productId: 'snipfit_pro_yearly',
    title: 'Snipfit Pro Yearly',
    priceString: '29,99 €',
    period: PlanPeriod.year,
    monthlyEquivalentString: '2,50 €',
  );
  static const monthly = Plan(
    kind: PlanKind.monthly,
    productId: 'snipfit_pro_monthly',
    title: 'Snipfit Pro Monthly',
    priceString: '4,99 €',
    period: PlanPeriod.month,
  );
  static const credits = Plan(
    kind: PlanKind.credits,
    productId: 'snipfit_credits_20',
    title: '20 AI credits',
    priceString: '4,99 €',
    period: PlanPeriod.none,
  );

  @override
  bool get available => true;

  @override
  Future<void> identify(String uid) async {}

  @override
  Future<PaywallOffer?> loadOffer({String offeringId = '', String creditsOfferingId = 'credits'}) async => offer;

  @override
  Future<PurchaseOutcome> purchase(Plan plan) async {
    purchased.add(plan.productId);
    return PurchaseOutcome.success;
  }

  @override
  Future<bool> restore() async => false;

  @override
  Stream<bool> get proStatus => Stream.value(false);

  @override
  Future<Uri?> managementUrl() async => null;
}

void main() {
  const offer = PaywallOffer(yearly: FakePurchases.yearly, monthly: FakePurchases.monthly, credits: FakePurchases.credits);

  testWidgets('close button is visible from the first frame', (tester) async {
    await pumpScreen(
      tester,
      const PaywallScreen(trigger: 'test'),
      overrides: [purchasesServiceProvider.overrideWithValue(FakePurchases(offer: offer))],
    );
    expect(find.byKey(const Key('paywall-close')), findsOneWidget);
  });

  testWidgets('yearly is preselected with its monthly equivalent and a priced action button', (tester) async {
    final env = await pumpScreen(
      tester,
      const PaywallScreen(trigger: 'test'),
      overrides: [purchasesServiceProvider.overrideWithValue(FakePurchases(offer: offer))],
    );
    await tester.ensureVisible(find.byKey(const Key('paywall-buy')));
    await tester.pumpAndSettle();
    expect(find.text('29,99 €/year'), findsOneWidget);
    expect(find.text('2,50 € per month, billed yearly'), findsOneWidget);
    expect(find.text('Subscribe for 29,99 €/year'), findsOneWidget);
    expect(env.analytics.events, contains(AnalyticsEvents.paywallViewed));
  });

  testWidgets('disclosure under the button: plan, length, price per period, auto-renewal, how to cancel', (tester) async {
    await pumpScreen(
      tester,
      const PaywallScreen(trigger: 'test'),
      overrides: [purchasesServiceProvider.overrideWithValue(FakePurchases(offer: offer))],
    );
    await tester.ensureVisible(find.byKey(const Key('paywall-disclosure')));
    await tester.pumpAndSettle();
    final disclosure = tester.widget<Text>(find.byKey(const Key('paywall-disclosure'))).data!;
    expect(disclosure, contains('Snipfit Pro Yearly'));
    expect(disclosure, contains('1 year'));
    expect(disclosure, contains('29,99 € per year'));
    expect(disclosure, contains('Renews automatically'));
    expect(disclosure, contains('until you cancel'));
    expect(find.textContaining('Cancel anytime in your App Store or Google Play'), findsOneWidget);
  });

  testWidgets('switching to monthly updates the button and disclosure', (tester) async {
    await pumpScreen(
      tester,
      const PaywallScreen(trigger: 'test'),
      overrides: [purchasesServiceProvider.overrideWithValue(FakePurchases(offer: offer))],
    );
    await tester.ensureVisible(find.text('Snipfit Pro Monthly'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Snipfit Pro Monthly'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('paywall-disclosure')));
    await tester.pumpAndSettle();
    expect(find.text('Subscribe for 4,99 €/month'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('paywall-disclosure'))).data, contains('4,99 € per month'));
  });

  testWidgets('Terms, Privacy and Restore links are present, plus the credit pack', (tester) async {
    await pumpScreen(
      tester,
      const PaywallScreen(trigger: 'test'),
      overrides: [purchasesServiceProvider.overrideWithValue(FakePurchases(offer: offer))],
    );
    // Free features are clearly separated from paid ones.
    expect(find.textContaining('Free forever'), findsOneWidget);
    // Live AR is not advertised until it ships.
    expect(find.text('Live AR try-on'), findsNothing);
    await tester.scrollUntilVisible(find.text('Restore purchases'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Terms of Use'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Restore purchases'), findsOneWidget);
    expect(find.text('Buy 20 AI credits · 4,99 €'), findsOneWidget);
  });

  testWidgets('without store products, purchases are unavailable but the screen still closes', (tester) async {
    await pumpScreen(
      tester,
      const PaywallScreen(trigger: 'test'),
      overrides: [purchasesServiceProvider.overrideWithValue(FakePurchases())],
    );
    expect(find.textContaining("Purchases aren't available"), findsOneWidget);
    expect(find.byKey(const Key('paywall-close')), findsOneWidget);
    expect(find.byKey(const Key('paywall-buy')), findsNothing);
  });
}

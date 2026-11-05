import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// RevenueCat entitlement that unlocks Pro.
const kProEntitlement = 'pro';

enum PlanKind { yearly, monthly, credits }

enum PlanPeriod { year, month, none }

/// A free trial or intro offer attached to a plan.
@immutable
class IntroOffer {
  const IntroOffer({required this.priceString, required this.isFree, required this.units, required this.unit});

  final String priceString;
  final bool isFree;
  final int units;
  final PlanPeriod unit;
}

/// One purchasable product, with every price string loaded from the store
/// (localized). Prices are never hardcoded.
@immutable
class Plan {
  const Plan({
    required this.kind,
    required this.productId,
    required this.title,
    required this.priceString,
    required this.period,
    this.monthlyEquivalentString,
    this.intro,
    this.native,
  });

  final PlanKind kind;
  final String productId;
  final String title;
  final String priceString;
  final PlanPeriod period;

  /// Yearly plans: the per-month equivalent, e.g. "$2.50".
  final String? monthlyEquivalentString;
  final IntroOffer? intro;

  /// The underlying RevenueCat package.
  final Object? native;
}

@immutable
class PaywallOffer {
  const PaywallOffer({this.yearly, this.monthly, this.credits});

  final Plan? yearly;
  final Plan? monthly;
  final Plan? credits;

  bool get isEmpty => yearly == null && monthly == null && credits == null;
}

enum PurchaseOutcome { success, cancelled, pending, failed, unavailable }

abstract class PurchasesService {
  bool get available;
  Future<void> identify(String uid);
  Future<PaywallOffer?> loadOffer({String offeringId = '', String creditsOfferingId = 'credits'});
  Future<PurchaseOutcome> purchase(Plan plan);

  /// Restores purchases; returns whether Pro is active afterwards.
  Future<bool> restore();
  Stream<bool> get proStatus;
  Future<Uri?> managementUrl();
}

class UnavailablePurchasesService implements PurchasesService {
  const UnavailablePurchasesService();

  @override
  bool get available => false;

  @override
  Future<void> identify(String uid) async {}

  @override
  Future<PaywallOffer?> loadOffer({String offeringId = '', String creditsOfferingId = 'credits'}) async => null;

  @override
  Future<PurchaseOutcome> purchase(Plan plan) async => PurchaseOutcome.unavailable;

  @override
  Future<bool> restore() async => false;

  @override
  Stream<bool> get proStatus => Stream.value(false);

  @override
  Future<Uri?> managementUrl() async => null;
}

class RevenueCatPurchasesService implements PurchasesService {
  RevenueCatPurchasesService._();

  final _pro = StreamController<bool>.broadcast();
  bool _lastPro = false;

  static Future<RevenueCatPurchasesService> start({required String apiKey}) async {
    await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.warn);
    await Purchases.configure(PurchasesConfiguration(apiKey));
    final service = RevenueCatPurchasesService._();
    Purchases.addCustomerInfoUpdateListener(service._onInfo);
    unawaited(Purchases.getCustomerInfo().then(service._onInfo).catchError((_) {}));
    return service;
  }

  void _onInfo(CustomerInfo info) {
    _lastPro = info.entitlements.active.containsKey(kProEntitlement);
    _pro.add(_lastPro);
  }

  @override
  bool get available => true;

  /// The RevenueCat app user ID is the Firebase UID, so the webhook can
  /// credit the right Firestore ledger.
  @override
  Future<void> identify(String uid) async {
    final current = await Purchases.appUserID;
    if (current == uid) return;
    final result = await Purchases.logIn(uid);
    _onInfo(result.customerInfo);
  }

  @override
  Future<PaywallOffer?> loadOffer({String offeringId = '', String creditsOfferingId = 'credits'}) async {
    final offerings = await Purchases.getOfferings();
    final main = offeringId.isNotEmpty ? (offerings.all[offeringId] ?? offerings.current) : offerings.current;
    final creditsOffering = offerings.all[creditsOfferingId];
    Plan? fromPackage(Package? p, PlanKind kind) {
      if (p == null) return null;
      final sp = p.storeProduct;
      final intro = sp.introductoryPrice;
      return Plan(
        kind: kind,
        productId: sp.identifier,
        title: sp.title,
        priceString: sp.priceString,
        period: switch (kind) {
          PlanKind.yearly => PlanPeriod.year,
          PlanKind.monthly => PlanPeriod.month,
          PlanKind.credits => PlanPeriod.none,
        },
        monthlyEquivalentString: kind == PlanKind.yearly ? sp.pricePerMonthString : null,
        intro: intro == null
            ? null
            : IntroOffer(
                priceString: intro.priceString,
                isFree: intro.price == 0,
                units: intro.periodNumberOfUnits * intro.cycles,
                unit: switch (intro.periodUnit) {
                  PeriodUnit.year => PlanPeriod.year,
                  PeriodUnit.month => PlanPeriod.month,
                  _ => PlanPeriod.none,
                },
              ),
        native: p,
      );
    }

    return PaywallOffer(
      yearly: fromPackage(main?.annual, PlanKind.yearly),
      monthly: fromPackage(main?.monthly, PlanKind.monthly),
      credits: fromPackage(creditsOffering?.availablePackages.firstOrNull, PlanKind.credits),
    );
  }

  @override
  Future<PurchaseOutcome> purchase(Plan plan) async {
    final package = plan.native;
    if (package is! Package) return PurchaseOutcome.unavailable;
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      _onInfo(result.customerInfo);
      return PurchaseOutcome.success;
    } on PlatformException catch (e) {
      return switch (PurchasesErrorHelper.getErrorCode(e)) {
        PurchasesErrorCode.purchaseCancelledError => PurchaseOutcome.cancelled,
        PurchasesErrorCode.paymentPendingError => PurchaseOutcome.pending,
        _ => PurchaseOutcome.failed,
      };
    }
  }

  @override
  Future<bool> restore() async {
    final info = await Purchases.restorePurchases();
    _onInfo(info);
    return _lastPro;
  }

  @override
  Stream<bool> get proStatus async* {
    yield _lastPro;
    yield* _pro.stream;
  }

  @override
  Future<Uri?> managementUrl() async {
    try {
      final url = (await Purchases.getCustomerInfo()).managementURL;
      if (url != null) return Uri.parse(url);
    } on PlatformException {
      // Fall through to the store's own page.
    }
    return null;
  }
}

final purchasesServiceProvider = Provider<PurchasesService>((ref) => const UnavailablePurchasesService());

final proStatusProvider = StreamProvider<bool>((ref) => ref.watch(purchasesServiceProvider).proStatus);

/// Store pages where a subscription can be cancelled, as a fallback when
/// RevenueCat has no management URL.
Uri storeSubscriptionsPage({required String androidPackage}) => Platform.isIOS
    ? Uri.parse('https://apps.apple.com/account/subscriptions')
    : Uri.parse('https://play.google.com/store/account/subscriptions?package=$androidPackage');

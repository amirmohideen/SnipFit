import '../paywall/entitlements.dart';

/// The single place that decides whether an AI try-on may start, in the
/// order the user should resolve things. The server re-checks every one of
/// these; this only drives the UI.
enum AiGate {
  /// Kill switch off, Firebase not configured, or this device can't run it.
  unavailable,

  /// AI features are for adults (18+) only.
  notAdult,

  /// Account suspended after repeated blocked requests.
  suspended,

  /// One-time AI consent (re-asked when its text changes).
  needsConsent,

  /// Needs Pro allowance or a credit.
  needsCredits,

  /// Needs a reference photo of the person.
  needsReference,
  ready,
}

AiGate evaluateAiGate({
  required bool featureEnabled,
  required bool backendReady,
  required bool isAdult,
  required bool aiConsent,
  required Entitlements entitlements,
  required bool hasReferencePhoto,
}) {
  if (!featureEnabled || !backendReady) return AiGate.unavailable;
  if (!isAdult) return AiGate.notAdult;
  if (entitlements.suspended) return AiGate.suspended;
  if (!aiConsent) return AiGate.needsConsent;
  if (entitlements.aiTryOnsAvailable <= 0) return AiGate.needsCredits;
  if (!hasReferencePhoto) return AiGate.needsReference;
  return AiGate.ready;
}

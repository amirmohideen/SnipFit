/// Funnel events. Properties never include images, names, emails, or
/// anything that identifies a person. Keep this list in sync with the
/// PostHog funnels described in docs/ANALYTICS.md.
abstract final class AnalyticsEvents {
  // Onboarding
  static const onboardingStepViewed = 'onboarding_step_viewed';
  static const ageConfirmed = 'age_confirmed';
  static const termsAccepted = 'terms_accepted';
  static const modeSelected = 'mode_selected';

  // Core
  static const captureStarted = 'capture_started';
  static const cutoutCompleted = 'cutout_completed';
  static const refineUsed = 'refine_used';
  static const liveWindowOpened = 'live_window_opened';
  static const compareSaved = 'compare_saved';

  // Growth
  static const shareOpened = 'share_opened';
  static const shareCompleted = 'share_completed';
  static const inviteOpened = 'invite_opened';

  // Money
  static const paywallViewed = 'paywall_viewed';
  static const purchaseStarted = 'purchase_started';
  static const purchaseCompleted = 'purchase_completed';
  static const restoreTapped = 'restore_tapped';

  // AI
  static const aiConsentGiven = 'ai_consent_given';
  static const aiTryonRequested = 'ai_tryon_requested';
  static const aiTryonSucceeded = 'ai_tryon_succeeded';
  static const aiTryonBlocked = 'ai_tryon_blocked';
  static const aiTryonFailed = 'ai_tryon_failed';
  static const reportSubmitted = 'report_submitted';
}

/// Property keys allowed in events. Anything else is dropped by
/// [AnalyticsPropertyFilter] so a careless call can't leak personal data.
abstract final class AnalyticsProps {
  static const step = 'step';
  static const mode = 'mode';
  static const source = 'source';
  static const quality = 'quality';
  static const format = 'format';
  static const target = 'target';
  static const trigger = 'trigger';
  static const product = 'product';
  static const reason = 'reason';
  static const tool = 'tool';
  static const isAdult = 'is_adult';
  static const variant = 'variant';
  static const count = 'count';

  static const allowed = {
    step,
    mode,
    source,
    quality,
    format,
    target,
    trigger,
    product,
    reason,
    tool,
    isAdult,
    variant,
    count,
  };
}

abstract final class AnalyticsPropertyFilter {
  /// Keeps only allow-listed keys with primitive values.
  static Map<String, Object> clean(Map<String, Object?>? props) {
    if (props == null) return const {};
    final out = <String, Object>{};
    props.forEach((key, value) {
      if (!AnalyticsProps.allowed.contains(key) || value == null) return;
      if (value is num || value is bool) {
        out[key] = value;
      } else if (value is String && value.length <= 64) {
        out[key] = value;
      } else if (value is Enum) {
        out[key] = value.name;
      }
    });
    return out;
  }
}

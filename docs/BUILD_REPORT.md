# Build report

*November 5, 2026. Built from [SPEC.md](../SPEC.md) in a cloud container (Linux, no macOS, no phone or emulator).*

The spec asks for a report at the end of each phase after running on an iPhone and an Android phone. That run hasn't happened: this environment has no devices, no macOS and no Android SDK. This report separates what was **verified here** from what still has to be **checked on devices**. Phases 1–7 are written; phase 8 (after launch) is deliberately not built.

## Verified in this environment

| Check | Result |
|---|---|
| `flutter analyze` (Flutter 3.47.9, Dart 3.13.7) | No issues |
| Flutter unit + widget tests (`./tool/test.sh`) | **52 passed** |
| Cloud Functions typecheck + build (TypeScript 5.9) | Clean |
| Cloud Functions tests (vitest) | **27 passed** |
| Localization check (`tool/check_l10n.py`) | 296 keys × 5 languages, placeholders match |
| Screens and share outputs rendered from the real code (`test_screens/`) | 11 renders, reviewed visually; see `docs/screenshots/` |
| iOS project wiring (`tool/ios_configure.rb` via the xcodeproj gem) | 9 build configurations, dev/prod schemes, plists valid |

The widget tests caught two real layout bugs (the paywall hero and plan tiles overflowed at phone width and with large text), and the visual review caught accent color creeping onto the live window. All three are fixed.

## Not verified here (needs your Mac and phones)

- **Compiling the apps.** No Android SDK could be installed (the network policy blocks `dl.google.com`) and iOS needs Xcode. The Kotlin (425 lines) and Swift (323 lines) native modules have never been compiled. CI is set up to build and launch both apps on push.
- **Real segmentation quality and speed.** The mask pipeline is tested on synthetic class maps; `face_detection_tflite` inference only runs on a device. The 9-in-10 clean-mask bar, 1.5 s cutout, 30 fps live window and 2 s cold start all need the device matrix and the ~200-photo test set.
- **Native features:** reveal-video encoding (MediaCodec / AVAssetWriter), Instagram Stories sharing, tap-to-select (MediaPipe Interactive Segmenter / Vision), Sign in with Apple / Google, push.
- **Backend against real services:** RevenueCat sandbox purchases, the webhook, Vertex AI Virtual Try-On, Cloud Vision and the coverage service. The Vertex AI request format follows the documented REST shape, but the docs site was unreachable from here, so confirm the model ID and parameters (`TRYON_MODEL`, `GEMINI_IMAGE_MODEL`).

## Phase by phase

### 1. Setup
**Built:** Flutter 3.47 project (iOS 16+, Android minSdk 24 / target 36); `dev`/`prod` flavors on both platforms with per-flavor bundle IDs and config (`config/*.json` via `--dart-define-from-file`); bootstrap where Firebase, RevenueCat and PostHog are all optional (local-only mode); Crashlytics, PostHog (replay off, consent-gated) and Remote Config wiring; design system (neutral chrome, one clay accent, Plus Jakarta Sans + IBM Plex Sans Arabic, 5-step type scale, 56 pt pill buttons, 16 pt radius, 8 pt grid, reduce-motion aware); CI (analyze, test, build and launch on Android emulator and iOS simulator), signed release workflow, backend deploy workflow; legal pages.
**Left:** Firebase projects, `flutterfire configure`, signing, first CI run ([OWNER_SETUP.md](OWNER_SETUP.md)).

### 2. Free core
**Built:** capture (front camera, face-and-shoulders guide, upload, flip, "someone else" with a permission confirmation every time); photo checks with one-line fixes (one face, light, frontal, distance); segmentation via `face_detection_tflite` (multi-class selfie model, GPU on iOS / CPU on Android) behind a `SegmentationEngine` interface; pure-Dart mask builder for the three strategies (garment in the torso region; worn hijab = hair/clothes/accessories in the head-and-neck envelope with eyes, brows and glasses protected; hijab templates Classic wrap, Khimar, Shayla as editable vector shapes aligned to the eyes); cleanup (open, close, hole fill, main components) and inward distance-transform feathering; the **no-skin invariant** applied last on every path, including after brush strokes; automatic detection of whether a hijab is worn, with a one-tap switch; Refine (brush, eraser, template handles, undo, redo, reset to auto, softness, two-finger zoom); live window (rear camera, drag/pinch/rotate, lock, tap-to-focus, exposure+focus lock, torch, fresh-selfie tip, three built-in demo fabrics); WYSIWYG capture compositing with metadata-free JPEGs and trimmed-mean fabric color with hex; 2×2 compare with a single favorite; private storage excluded from backups; Save to Photos with add-only access, asked only on tap. Landmarks and class maps never leave memory.
**Left:** device tuning and the test-set bar; install-size check (see decision 3).

### 3. Onboarding, legal, Settings
**Built:** hook animation (paper cutout → phone, 5 s loop), neutral birth-year picker (nothing preselected, under-13 blocked for a day, only the 18+ flag kept, youngest-possible-age rule), terms clickwrap (3 bullets, links, unticked box, versioned log), EU/UK analytics opt-in, mode picker (Men behind a flag), camera explainer ("Continue", never "Allow") with a denied state, biometric consent before any face processing (enforced by the router), guided first capture with coach mark and "Your window is ready", practice overlay with demo fabric, soft paywall once after the first compare, notification ask only after a saved comparison, versioned consent records synced append-only to Firestore (offline-first). Settings: account linking, deletion, manage subscription, restore, credit balance, analytics / AI / face-processing consent withdrawal, delete local photos, How it works replay, legal, licenses, theme, language. Drafts of Terms, Privacy Policy, Biometric Notice and AI Disclosure, all marked **DRAFT, pending legal review**, bundled and hosted. English, Arabic (RTL), Turkish, Malay, Indonesian.
**Left:** lawyer review; native-speaker review of translations; start Google Play's 14-day closed test with 12 testers.

### 4. Sharing
**Built:** reveal video (6.8 s, 9:16, 30 fps: printed photo, traced cut line with scissors, fabric reveal, swatch ending), compare collage (9:16 and 1:1), single result with swatch and hex; "Made with Snipfit" watermark placed in the corner that avoids the face and fabric (removed for Pro); share sheet with Instagram Stories, TikTok, Snapchat, WhatsApp and More; caption + invite link copied with a notice; metadata-free exports; someone-else reminder; invite links (`/i/<code>?m=<mode>`) with universal links, App Links and a landing page that routes to each mode's store page; native review prompt only after a favorite.
**Left:** Meta App ID; TikTok Share Kit and Snap Creative Kit registration and SDKs ([SHARE_KITS.md](SHARE_KITS.md)); a licensed sound if you want audio (none is bundled).

### 5. Paywall and Pro
**Built:** RevenueCat purchases (app user = Firebase UID), compliant paywall per the spec's 7-point layout (close button from the first frame, hero, 3 benefits, yearly preselected with monthly equivalent, action-and-price button, full disclosure, Terms/Privacy/Restore, plus Manage subscription and the credit pack), store-loaded localized prices only, offering switch via Remote Config, free-trial variant behind a PostHog experiment, live AR line hidden until it ships. Server ledger: reserve / commit / release so a credit is spent only on success and refunded on failure or block; Pro's 30 monthly try-ons reset monthly even on yearly plans; webhook (bearer auth, idempotent) is the only credit grantor; Firestore rules keep balances server-only.
**Left:** products, entitlement, offerings and webhook in RevenueCat; sandbox runs of purchase, renewal, restore and refund.

### 6. AI try-on
**Built:** gate (feature flag, backend, 18+, suspension, AI consent, credits, reference photo) shared by UI and server; one-time AI consent naming Google Cloud Vertex AI, with timestamped records and re-ask on version change; reference photo kept on the device; tap-a-garment through the rear camera (native segmenters; hidden on unsupported devices with a gallery alternative) and "Is this the item?"; upload only after consent; `createTryOn` (App Check, auth, kill switch, age, consent version, inputs, per-user and per-device rate limits, global daily spend cap, credit reservation, task queue below Vertex AI's 50 rpm); `processTryOn` (SafeSearch and restricted-garment checks on inputs and outputs, Virtual Try-On with a Gemini fallback for hijabs, fixed server instructions, coverage check that blocks results showing more skin, XMP provenance, settle, delete inputs immediately, push when ready, suspension after repeated blocks); honest progress screen with "notify me"; result with True color vs AI look, visible "AI-generated" label, save/share with provenance, in-app Report; hourly sweep that deletes anything older than 23 hours and refunds stuck requests; account deletion including RevenueCat.
**Left:** enable APIs and quotas, deploy the Python coverage service, confirm the model and pricing, run the safety test set (vendor or synthetic images only) and confirm 24-hour deletion in staging.

### 7. Store preparation
**Built:** privacy manifest, purpose strings, [COMPLIANCE_CHECKLIST.md](COMPLIANCE_CHECKLIST.md), [STORE_REVIEW_NOTES.md](STORE_REVIEW_NOTES.md), [STORE_LISTING.md](STORE_LISTING.md) (Women default, Hijab custom page), [DATA_SAFETY.md](DATA_SAFETY.md), [APP_PRIVACY_LABELS.md](APP_PRIVACY_LABELS.md), account-deletion web page.
**Left:** real screenshots per mode, custom product pages, age-rating questionnaires, submission.

### 8. After launch
Not built, as the spec says: hijab live recolor, Snap Camera Kit garment transfer, friends-vote link. `live_ar_enabled` exists only as an off switch, and live AR is not advertised.

## Decisions needed from you

1. **Neck coverage in hijab templates.** The spec says the window must never include face *or body* skin, so for someone not wearing a hijab, the template leaves the neck showing between the scarf and the shoulders (visible in `docs/screenshots/06_refine_hijab_template.png`). Covering the neck only adds fabric and can't reveal anything, so I recommend allowing hijab templates (and only templates) to cover neck skin while still never covering the face. It's a one-line change in `MaskBuilder`, but it relaxes a hard rule, so it's your call.
2. **Bundle IDs and domain.** Placeholders `com.snipfit.app` and `snipfit.app` are used everywhere; confirm or give me the real ones.
3. **Install size.** `face_detection_tflite` bundles about 30 MB of models (including a face-recognition embedding model Snipfit never calls) plus OpenCV native libraries, against an 80 MB target. Measure the first release build; if it's over, take the spec's fallback: run only the three needed models through `flutter_litert` behind the same `SegmentationEngine` interface.
4. **Consent records on account deletion.** They're deleted today. Counsel may want proof of consent kept in a restricted archive.
5. **iPhone only.** The iOS target is iPhone-only (portrait, full screen). Say if you want iPad.
6. **RevenueCat's paywall UI package** isn't used: the spec dictates an exact layout and disclosures, so the paywall is custom and loads prices from RevenueCat. RevenueCat's paywall UI or Customer Center can still be added for experiments.
7. **Crash reporting consent.** Crashlytics follows the same EU/UK opt-in as analytics, to be conservative. Counsel may decide crash reports count as strictly necessary.

## Environment notes

- `dl.google.com` (Android SDK) and `docs.cloud.google.com` are blocked by this session's network policy. Allowing `dl.google.com` would let an Android build be verified in a cloud session.
- OpenCV's build hook compiles OpenCV for the host during `flutter test`; `tool/test.sh` sets dartcv4's documented `skip_build` for test runs only and restores `pubspec.yaml` afterwards.

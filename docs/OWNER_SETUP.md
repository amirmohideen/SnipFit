# Owner setup

Everything below needs your accounts, so it can't be done from the code. Work top to bottom; the app keeps working in local-only mode until each piece is connected. Placeholder IDs used in the code: bundle/package `com.snipfit.app` (`.dev` for the dev flavor) and domain `snipfit.app`. Change them first if you want different ones (search the repo for `com.snipfit.app` and `snipfit.app`).

## 1. Identity and domain

1. Register the domain (spec default `snipfit.app`) and point it at Firebase Hosting (step 3).
2. Apple Developer: create App IDs `com.snipfit.app` and `com.snipfit.app.dev` with **Associated Domains**, **Sign in with Apple** and **Push Notifications** capabilities. Put your Team ID into `hosting/public/.well-known/apple-app-site-association` (replace `TEAMID`) and `ios/ExportOptions.plist`.
3. Google Play Console: create the app `com.snipfit.app`. After the first upload, copy the **app signing** SHA-256 fingerprint into `hosting/public/.well-known/assetlinks.json`.

## 2. Firebase (two projects: dev and prod)

1. Create `snipfit-dev` and `snipfit-prod` (names in `.firebaserc`), Blaze plan.
2. Enable: Authentication (Anonymous, Apple, Google), Firestore, Storage, Functions, App Check, Remote Config, Crashlytics, Cloud Messaging, Hosting.
3. Generate config per flavor (this replaces the placeholders in `lib/firebase/`):
   ```bash
   flutterfire configure --project=snipfit-dev --out=lib/firebase/firebase_options_dev.dart --ios-bundle-id=com.snipfit.app.dev --android-package-name=com.snipfit.app.dev
   ```
   ```bash
   flutterfire configure --project=snipfit-prod --out=lib/firebase/firebase_options_prod.dart --ios-bundle-id=com.snipfit.app --android-package-name=com.snipfit.app
   ```
   Move each `google-services.json` to `android/app/src/<flavor>/` and keep `GoogleService-Info.plist` out of git. Copy `CLIENT_ID` and `REVERSED_CLIENT_ID` into `ios/config/<flavor>.xcconfig`.
4. App Check: Play Integrity (Android) and App Attest with DeviceCheck fallback (iOS). Register debug tokens for development devices. Every callable function enforces App Check.
5. Remote Config, client template (keys in `lib/core/flags/remote_flags.dart`): `men_mode_enabled` false, `ai_tryon_enabled` true, `live_ar_enabled` false, `soft_paywall_enabled` true, `reveal_video_enabled` true, `share_kits_enabled` true, `paywall_offering_id` "", `credits_offering_id` "credits", `trial_experiment_enabled` false.
6. Remote Config, **server** template (read by Cloud Functions, defaults in `functions/src/config.ts`): `ai_enabled`, `ai_daily_cap_usd` (spending cap, default 50), `ai_cost_per_image_usd` (0.06; confirm current pricing), `ai_user_hourly_limit` (6), `ai_device_daily_limit` (20), `ai_samples` (1 or 2), `tryon_provider_hijab` (`vertex_vto` or `gemini`), `ai_coverage_required` (true), `ai_suspend_after_blocks` (3).
7. Deploy rules, indexes, functions and hosting (or run the **Deploy backend** workflow):
   ```bash
   firebase deploy --project dev --only firestore,storage,functions,hosting
   ```
8. Storage lifecycle (belt and braces for the 24-hour deletion; the hourly sweep is the real guarantee):
   ```bash
   gcloud storage buckets update gs://snipfit-dev.firebasestorage.app --lifecycle-file=storage-lifecycle.json
   ```

## 3. Google Cloud AI (paid try-on)

1. In each project, enable **Vertex AI API** and **Cloud Vision API**; give the Cloud Functions service account the *Vertex AI User* role.
2. Confirm the Virtual Try-On model ID and request format in the current Vertex AI docs (default param `TRYON_MODEL=virtual-try-on-preview-08-04`), request quota above the default 50 requests/minute if needed, and confirm current pricing. Test hijabs specifically; if Virtual Try-On handles them poorly, set `tryon_provider_hijab` to `gemini` (model param `GEMINI_IMAGE_MODEL`).
3. Confirm which training and retention terms apply under your Google Cloud agreement, then finalize the matching sentence in `assets/legal/ai-disclosure.md` and the AI consent text.
4. Secrets and params:
   ```bash
   firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET --project dev
   ```
   ```bash
   firebase functions:secrets:set COVERAGE_SERVICE_TOKEN --project dev
   ```
   ```bash
   firebase functions:secrets:set REVENUECAT_SECRET_API_KEY --project dev
   ```
   After the first deploy, set `COVERAGE_SERVICE_URL` (the URL of the `coverage` function) when prompted on the next deploy, or in `functions/.env.<project>`.

## 4. RevenueCat and the stores

1. App Store Connect: subscription group "Snipfit Pro" with `snipfit_pro_yearly` ($29.99/year) and `snipfit_pro_monthly` ($4.99/month); consumable `snipfit_credits_20` ($4.99). Add Terms of Use (EULA) and Privacy Policy links to the app's metadata. Same products in Play Console.
2. RevenueCat: one project, apps for iOS and Android; entitlement **`pro`** attached to both subscriptions; offering `default` (current) with `$rc_annual` and `$rc_monthly` packages; offering `credits` with the credit pack. Put the public SDK keys into `config/dev.json` / `config/prod.json`.
3. Webhook: Project settings → Integrations → Webhooks → URL of `revenuecatWebhook`, Authorization header `Bearer <REVENUECAT_WEBHOOK_SECRET>`. Credits are granted only by this webhook.
4. Price tests: point `paywall_offering_id` (Remote Config) at another offering. Free-trial experiment: create the PostHog flag `paywall_trial` (variants `control`/`trial`), add an intro offer to the yearly product and set `trial_experiment_enabled` true.

## 5. PostHog

Create a project in the **EU** cloud (as named in the Privacy Policy; change both if you pick US). Put the project token and host into `config/*.json`. Session replay stays off in code. Build the funnels from [ANALYTICS.md](ANALYTICS.md).

## 6. Sharing

- Instagram Stories needs a Meta (Facebook) App ID in `FACEBOOK_APP_ID`.
- TikTok Share Kit and Snap Creative Kit need their own developer registration; see [SHARE_KITS.md](SHARE_KITS.md). Until then those buttons fall back to the system share sheet.
- Custom product pages (App Store) and custom store listings (Play) per mode: put their IDs in `config/prod.json` and `hosting/public/i/index.html`.

## 7. CI secrets

Listed at the top of `.github/workflows/release.yml` and `backend.yml`.

## 8. Before submission

Work through [COMPLIANCE_CHECKLIST.md](COMPLIANCE_CHECKLIST.md), have a lawyer review `assets/legal/` (then remove the DRAFT banners, bump versions in `lib/config/legal_versions.dart` and `ACCEPTED_AI_CONSENT_VERSIONS`, and run `tool/build_legal_pages.sh`), get native speakers to review the Arabic, Turkish, Malay and Indonesian strings, and start Google Play's 14-day closed test with 12 testers early.

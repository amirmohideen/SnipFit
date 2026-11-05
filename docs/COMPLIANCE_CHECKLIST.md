# Store compliance checklist (release gate)

Every box must be checked before the first submission, and re-checked whenever a feature is added. **Code** = implemented in this repo. **Owner** = needs your accounts, consoles or a lawyer. Nothing here is checked yet because none of it has been verified on a device or in a store console.

## Apple App Store

- [ ] **Third-party AI (5.1.2(i))**: before any photo reaches the server, an in-app screen says what is sent, names the provider, states the purpose and gets explicit opt-in. *Code:* `AiConsentScreen` (unticked checkbox, names Google Cloud Vertex AI, 24-hour deletion), shown before any upload; `createTryOn` rejects requests without a current AI consent record. *Owner:* confirm the Google Cloud terms sentence.
- [ ] **Subscriptions (3.1.2(c))**: title, length and price before purchase, working Privacy and Terms links. *Code:* `PaywallScreen` + widget tests. *Owner:* add the EULA and Privacy Policy URLs to App Store Connect metadata.
- [ ] **In-app account deletion (5.1.1(v))**, easy to find. *Code:* Settings → Delete account → `deleteAccount` function (incl. Sign in with Apple token revocation on iOS).
- [ ] **Sign in with Apple** offered alongside Google. *Code:* Settings → Account. *Owner:* enable the capability and the Firebase provider.
- [ ] **Privacy manifest** with required-reason APIs; privacy labels match behavior. *Code:* `ios/Runner/PrivacyInfo.xcprivacy`; answers in [APP_PRIVACY_LABELS.md](APP_PRIVACY_LABELS.md). *Owner:* check Xcode's generated privacy report (which merges the SDK manifests) against the labels.
- [ ] **Purpose strings** in plain words; photo selection through the system picker (no full library permission). *Code:* `Info.plist` has camera, add-only photos and the camera-plugin microphone note; uploads use the system picker.
- [ ] **Built with Xcode 26 and the iOS 26 SDK.** *Code:* CI and release workflows select Xcode 26. *Owner:* build locally on your Mac to confirm.
- [ ] **No undescribed hidden features**: describe flagged features (Men's mode, live AR flag, trial experiment, AI kill switch) in the review notes. *Draft:* [STORE_REVIEW_NOTES.md](STORE_REVIEW_NOTES.md).
- [ ] **Review notes** explain how to test AI try-on, the built-in demo fabric, and the safety system. *Draft:* [STORE_REVIEW_NOTES.md](STORE_REVIEW_NOTES.md).
- [ ] **Age rating** answered honestly, including AI image generation. *Owner.*

## Google Play

- [ ] **In-app Report on AI results** and filters that prevent restricted content. *Code:* Report button on the result screen → `reportResult`; SafeSearch + restricted-garment + coverage checks on inputs and outputs; fixed server-side instructions.
- [ ] **Account deletion** in the app plus a public web page, URL entered in the Data safety form. *Code:* Settings and `hosting/public/delete-account.html` (`https://snipfit.app/delete-account`).
- [ ] **Data safety form** matches behavior, including the AI upload and 24-hour deletion. *Draft:* [DATA_SAFETY.md](DATA_SAFETY.md).
- [ ] **Photo Picker** instead of broad photo permissions. *Code:* no `READ_MEDIA_*` permissions; `image_picker` uses the system Photo Picker; saving uses MediaStore.
- [ ] **Target audience 13+**, not children; content rating questionnaire. *Owner.*
- [ ] **Current target API level; App Bundle.** *Code:* targetSdk 36, release workflow builds `.aab`.
- [ ] **14-day closed test with at least 12 testers** (new personal developer accounts). *Owner:* start early.

## Both stores

- [ ] **Privacy Policy URL** in both consoles; Terms reachable in-app without an account. *Code:* `/legal/*` routes need no account or consent; hosted at `https://snipfit.app/legal/privacy`.
- [ ] **Screenshots** show the real app and clothed results only; no listing copy implying clothing removal. *Draft copy:* [STORE_LISTING.md](STORE_LISTING.md).
- [ ] **No feature, reward or credit requires sharing, rating or reviewing.** *Code:* review prompt only via the native API after a positive moment (a favorite), at most every 120 days; nothing is gated on sharing.
- [ ] **Custom product pages / custom store listings per mode** (Women default, Hijab, later Men) with matching screenshots. *Owner:* create them; put the IDs into `config/prod.json` and `hosting/public/i/index.html`.

## Product safety rules (hard requirements)

- [x] Window only covers clothing classes or a hijab template, never face or body skin. *Code + tests:* `MaskBuilder.enforceNoSkin` runs last on every path, after brush edits and feathering (`test/unit/mask_test.dart`).
- [x] Exports are always finished composites; no transparent cutout file is ever exported. *Code:* `ExportService` only renders composites; cutouts stay in private storage.
- [x] Users never type prompts, upload masks or choose what to remove. *Code:* `fixedInstruction()` on the server; the client sends only two photos.
- [x] AI results must cover at least as much as the original clothing. *Code + tests:* `judgeCoverage` with the coverage service; fail-closed when the service isn't configured.
- [x] No swimwear, underwear or lingerie. *Code + tests:* `RESTRICTED_LABELS`.
- [x] None of the wording banned in SPEC.md ("Safety guardrails") appears in app copy, listings, code or comments. *Check:* search the repo for each banned term; only SPEC.md should match.
- [x] Every AI image is labeled visibly and with machine-readable provenance. *Code + tests:* "AI-generated" label, IPTC `trainedAlgorithmicMedia` XMP on server and client exports, model SynthID watermark.

These are checked because they're enforced in code and covered by tests. They still need the device and staging tests in [BUILD_REPORT.md](BUILD_REPORT.md).

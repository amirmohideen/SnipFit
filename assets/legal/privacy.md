> **DRAFT, pending legal review.** This document has not been reviewed by a lawyer. Placeholders in [brackets] must be completed before launch.

# Snipfit Privacy Policy

*Version 2026-11-05-draft. Last updated: November 5, 2026.*

This policy explains what information Snipfit ("we", "us", [Snipfit LLC]) handles, why, and your choices. Snipfit is built to be **private by default**: photos are processed on your phone and are not uploaded unless you start a paid AI try-on and agree first.

## 1. What stays on your phone

| Information | Where it's processed | Stored? |
|---|---|---|
| Photos you take or upload for a cutout | On your phone only | Your photo and the finished cutout ("window") are saved in the app's private storage on your phone until you delete them. Excluded from device backups. |
| Face landmarks and body/clothing segmentation | On your phone, in memory only | **Never stored, never sent.** See our [Biometric Notice](https://snipfit.app/legal/biometric-notice). |
| Live camera view, captures, compare grid | On your phone only | Captures are saved in the app's private storage until you delete them. |
| Fabric color samples (swatch and hex code) | On your phone only | Saved with each capture. |
| Your AI try-on reference photo | On your phone | Stored on your phone; sent only when you start a try-on (below). |

Saving to your photo library happens only when you tap **Save to Photos**, using add-only access. Everything you share is created on your phone and contains no location or camera metadata.

## 2. What we collect, and why

| Data | Purpose | Legal basis (EU/UK) | Retention |
|---|---|---|---|
| **AI try-on inputs**: your try-on photo and the garment photo, only after you agree on the AI consent screen | Create your AI preview; run safety checks (adult/violent content, restricted garments, a check that the result shows no more skin than the original) | Contract; explicit consent | **Deleted within 24 hours** |
| **AI try-on results** | Deliver your preview | Contract | Deleted from our servers within 24 hours (copies you save stay on your phone) |
| **Account ID**: a random ID from Firebase anonymous sign-in; if you choose, the link to your Apple or Google sign-in | Keep your credits and subscription status | Contract | Until you delete your account |
| **Purchase records**: subscription status, credit balance and ledger, store transaction IDs | Provide what you paid for; fraud prevention | Contract; legal obligation | Until account deletion, then as required for tax/accounting [counsel: confirm period] |
| **Consent records**: which version of the Terms, Biometric Notice and AI consent you accepted, when, app version and language; whether you are 18+ (not your birth year) | Prove and respect your choices | Legal obligation; legitimate interest | Until account deletion [counsel: confirm whether to keep proof of consent longer] |
| **Push token** (only if you turn on notifications) | Tell you when an AI try-on is ready | Consent | Until you turn notifications off or delete your account |
| **Product analytics**: screens and steps used (for example "terms_accepted", "share_completed"), device type, app version, approximate region from IP | Improve the app | Consent (EU/UK); legitimate interest elsewhere, with opt-out in Settings | [counsel: confirm, e.g. 12 months] |
| **Crash reports**: technical details of crashes | Fix bugs | Legitimate interest (consent in the EU/UK) | 90 days |
| **Reports you submit** on AI results (the reason you chose) | Moderation and improving filters | Legitimate interest | [counsel: confirm, e.g. 12 months] |
| **Support emails** | Help you | Legitimate interest | As long as needed to help you |

Analytics events **never** include photos, names, email addresses or anything that identifies you. Session replay and screen capture are turned off.

We do **not** sell or rent personal information, we do **not** share it for cross-context behavioral advertising, and we do **not** track you across other companies' apps or websites.

## 3. Who processes data for us

| Processor | What for | Data |
|---|---|---|
| **Google Cloud** (Firebase, Cloud Functions, Cloud Storage, Firestore) | Hosting, accounts, credit ledger, temporary storage of AI inputs/results | Account ID, purchase records, consent records, AI inputs/results (24 h) |
| **Google Cloud Vertex AI** (Virtual Try-On; Gemini image models as a fallback) | Generating AI previews | AI inputs and results (24 h) |
| **Google Cloud Vision** | Safety checks on AI inputs and results | AI inputs and results (processed, not stored) |
| **Firebase Crashlytics, Remote Config, Cloud Messaging, App Check** | Crash reports, feature switches, notifications, abuse prevention | Crash data, push token, app integrity signals |
| **RevenueCat** | Managing subscriptions and purchases with Apple and Google | Account ID, purchase records |
| **PostHog** ([EU] cloud region) | Product analytics | Analytics events |
| **Apple, Google** | App stores, payments, optional sign-in | As set by their own policies |

[Counsel/owner: confirm each vendor's data processing agreement and the Google Cloud terms that apply, including that customer data is not used to train Google's models.]

## 4. International transfers

We are based in the United States and our processors may process data in the US and other countries. Where required (for example for EU/UK data), we rely on appropriate safeguards such as the EU Standard Contractual Clauses or the EU-US Data Privacy Framework. [Counsel: confirm.]

## 5. Security

Data in transit is encrypted (TLS). Server access is restricted, every AI request is verified with Firebase App Check and sign-in, and AI inputs live in storage that only our servers can read. Logs contain no images and only shortened, hashed user IDs.

## 6. Children

Snipfit is not for children under 13, and we do not knowingly collect personal information from them. AI features are for adults (18+). Our Terms forbid using photos of anyone under 18. If you believe a child has given us information, contact us and we will delete it.

## 7. Your rights and choices

- **On your phone:** delete windows, captures and AI results at any time (Settings → Delete photos on this phone).
- **Account deletion:** Settings → Delete account, or https://snipfit.app/delete-account. This deletes your account, credits, consent records and any data on our servers.
- **Withdraw consent:** turn off AI try-on processing, face processing or analytics in Settings at any time.
- **EU/UK (GDPR):** you can request access, correction, deletion, restriction or portability of your data, object to processing, and complain to your data protection authority.
- **California (CCPA/CPRA):** you have the right to know, delete, correct and limit use of sensitive personal information, and not to be discriminated against for using these rights. We do not sell or share personal information.
- **Other regions** (including Turkey's KVKK, Malaysia's PDPA and Indonesia's PDP Law): you may have similar rights. [Counsel: confirm local requirements, e.g. data-controller registration.]

To use these rights, email [privacy@snipfit.app](mailto:privacy@snipfit.app). We may need to verify your request.

## 8. Changes

If we change this policy materially, we'll tell you in the app before the change applies.

## 9. Contact

[Snipfit LLC], [postal address]. Email: [privacy@snipfit.app](mailto:privacy@snipfit.app). [EU/UK representative, if required.]

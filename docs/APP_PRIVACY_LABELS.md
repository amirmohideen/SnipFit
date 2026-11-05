# App Store privacy "nutrition label" answers (draft)

Keep in sync with `ios/Runner/PrivacyInfo.xcprivacy` and the Privacy Policy. Tracking: **No** (no cross-app tracking, no ad attribution SDK; adding one later needs the App Tracking Transparency prompt).

| Data type | Collected | Linked to the user | Used for tracking | Purposes |
|---|---|---|---|---|
| Photos or Videos | Yes (paid AI try-on only, after consent; deleted within 24 h) | Yes | No | App Functionality |
| User ID | Yes (pseudonymous Firebase account ID) | Yes | No | App Functionality |
| Purchase History | Yes (RevenueCat) | Yes | No | App Functionality |
| Product Interaction | Yes (PostHog, consent-gated in EU/UK) | Yes | No | Analytics |
| Crash Data | Yes (Crashlytics) | No | No | App Functionality |
| Other Data Types | Yes (consent records, 18+ flag) | Yes | No | App Functionality |

Not collected: contact info, location, health, sensitive info, browsing history, search history, contacts, audio. Face processing for the free cutout happens on the device only and is never collected.

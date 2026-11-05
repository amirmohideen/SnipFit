# Google Play Data safety answers (draft)

Matches the code as built; re-check whenever a feature changes. Encryption in transit: **yes**. Users can request deletion: **yes** (in app and https://snipfit.app/delete-account). Data shared with third parties (as defined by Play): **no** (all listed vendors are service providers processing on our behalf).

| Data type | Collected | Optional? | Purpose | Retention notes |
|---|---|---|---|---|
| Photos | Yes, only for paid AI try-on after consent | Optional | App functionality | Deleted within 24 hours |
| App activity: app interactions | Yes | Optional (consent in EU/UK, opt-out elsewhere) | Analytics | PostHog |
| App info and performance: crash logs, diagnostics | Yes | Optional in EU/UK | App functionality | Crashlytics, 90 days |
| Device or other IDs | Yes (Firebase installation/push token, App Check) | Push token optional | App functionality, fraud prevention | Until deletion |
| Financial info: purchase history | Yes | Required for purchases | App functionality | RevenueCat; tax records as required |
| Personal info: user IDs | Yes (pseudonymous account ID) | Required for paid features | App functionality | Until deletion |
| Other: consent records (incl. 18+ flag, never the birth year) | Yes | Required | App functionality, legal compliance | Until deletion |

Not collected: location, contacts, messages, audio, health, web history, name, email (Apple/Google sign-in links an account but the app never reads the email), face or biometric data (processed only on the device, in memory).

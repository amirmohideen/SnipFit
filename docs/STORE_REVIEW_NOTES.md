# App Review notes (draft)

Paste into App Store Connect → App Review Information → Notes, and Play Console → App access. Fill in the bracketed parts.

---

**What Snipfit does.** Snipfit helps people see how a fabric color looks on them before buying. The app cuts the garment area (a top, or a hijab) out of the user's photo **on the device**, then overlays that cutout on the live rear camera so real fabric in a store shows through. The free features never upload photos.

**Testing away from a store.** On the live camera screen, tap the fabric icon (top right) to use a **built-in demo fabric**; tap again to cycle three fabrics. Any plain photo of a person works for the cutout; a demo photo is in the review attachments.

**Paid features.** Snipfit Pro (auto-renewing, yearly or monthly) and AI credit packs, sold through the App Store / Google Play via RevenueCat. Pro includes 30 AI try-ons a month and removes the watermark from shares. Sandbox account: [email / password].

**How to test AI try-on.**
1. Complete onboarding with a birth year that makes you 18+.
2. Home → AI try-on → accept the AI consent screen (it names Google Cloud Vertex AI and explains the 24-hour deletion).
3. Add a try-on photo (a clothed adult; one is in the attachments).
4. Tap a garment through the rear camera (iOS 17+ / most Android phones), or choose a garment photo from the gallery.
5. The result appears side by side with the free cutout, labeled "AI-generated", with a Report button.
A review account with credits: [describe, or we grant credits on request].

**Safety system.**
- The cutout window can only cover clothing or a hijab template, never face or body skin (enforced in code after every edit).
- AI instructions are fixed on our server. Users can't type prompts, upload masks or choose what to remove.
- Every input and output is checked with Google Cloud Vision SafeSearch (adult, racy, violent) and for restricted garments (swimwear, underwear, lingerie); a coverage check blocks any result that shows more skin than the original photo.
- Blocked or failed requests are refunded automatically; repeated blocked requests suspend AI features on the account.
- AI images carry a visible "AI-generated" label and IPTC provenance metadata (plus Google's SynthID watermark).
- AI features are for adults (18+) only, based on the age screen. Users confirm they have permission when using a photo of someone else.

**Features behind server switches** (so nothing is hidden from review): Men's mode (off at launch), live AR try-on (off, not advertised), a free-trial paywall experiment (off by default), and an AI kill switch and daily spending cap. Current state: [describe].

**Account deletion.** Settings → Delete account. Web: https://snipfit.app/delete-account

**Privacy.** Photos stay on the device unless the user starts a paid AI try-on and consents; AI inputs and results are deleted from our servers within 24 hours. Privacy Policy: https://snipfit.app/legal/privacy

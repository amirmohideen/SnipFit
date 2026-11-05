> **DRAFT, pending legal review.** This document has not been reviewed by a lawyer.

# Snipfit AI Disclosure

*Version 2026-11-05-draft. Last updated: November 5, 2026.*

This explains exactly what happens when you use **AI try-on**, a paid feature. The same summary is shown in the app before you agree.

## What is sent

Only when you start an AI try-on, after you agree on the AI consent screen:

1. **Your try-on photo**: one photo of you (or of an adult who gave permission), upper or full body, fully clothed.
2. **The garment photo**: the item you tapped in the store, cut out on your phone, or a garment photo you chose.

Nothing is sent before you tap **Use it** on a garment. The free cutout and live window never send anything.

## To whom

- **Our servers** on Google Cloud (Firebase), which check your account, age (18+), consent and credits.
- **Google Cloud Vertex AI** (the Virtual Try-On model, or a Gemini image model as a fallback for some garments such as hijabs), which creates the preview.
- **Google Cloud Vision**, which checks the photos and the result for adult or violent content and restricted garments (swimwear, underwear, lingerie).

## Why

Only to create your try-on preview and to make sure it is safe. We do not use your photos for advertising, we do not sell them, and we do not use them to train AI models. [Owner/counsel: confirm the Google Cloud terms that apply to this project, including Vertex AI's commitment not to use customer data to train models without permission, before publishing this sentence.]

## How long it's kept

- Your photos and the AI results are **deleted from our servers within 24 hours** (usually right after the result is delivered).
- Copies you save stay on your phone until you delete them.
- We keep a minimal record of each request (status, timing, which safety checks ran), with no images, for up to 30 days for support and abuse prevention.

## Safety

- Instructions to the AI are fixed by us. You can't type prompts, upload a mask or choose what to remove.
- Every result must cover **at least as much of the body** as the original clothing; results that show more skin are blocked.
- Requests that are blocked or fail are **refunded automatically**.
- Repeated blocked requests pause AI try-on on the account.
- You can **report** any AI result from the result screen.

## Labels

Every AI image is shown with a visible **"AI-generated"** label and carries machine-readable provenance information (IPTC "trained algorithmic media" metadata, plus Google's SynthID watermark). Please keep these labels when you share.

## Your choices

You can withdraw AI consent at any time in **Settings → AI try-on processing**, which turns AI features off.

Questions: [privacy@snipfit.app](mailto:privacy@snipfit.app).

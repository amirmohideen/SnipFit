> **DRAFT, pending legal review.** This document has not been reviewed by a lawyer.

# Snipfit Biometric Notice

*Version 2026-11-05-draft. Last updated: November 5, 2026.*

This notice applies to everyone, wherever you live. We ask for your explicit consent, with an unticked checkbox, before Snipfit processes a face for the first time.

## What we process

To make a cutout, Snipfit's on-device models find the face and body outline in your photo:

- **Face detection and face landmarks** (points such as the eyes and the face outline), used to check that the photo shows one person, facing the camera, in enough light, and to place hijab templates around the face.
- **Body and clothing segmentation**, which labels areas of the photo as hair, skin, clothing or background, used to find the garment area and to make sure the cutout never covers skin.

## Where and how long

- This processing happens **only on your phone**, in memory, while your window is being made.
- Face landmarks and segmentation maps are **never stored and never sent** to us or anyone else. They are discarded as soon as your window is ready.
- What the app saves on your phone is your photo and the finished cutout, until you delete them.

## What we never do

- We never use this processing to **identify** you or anyone else, and we never build a face database.
- We never **sell, rent, trade or share** face data.
- We never use it for advertising.

## AI try-on (separate consent)

Paid AI try-on is different: with a separate consent, your try-on photo and the garment photo are sent to our servers and to Google Cloud's AI service to create a preview. Our servers do not run face recognition on them. They are deleted within 24 hours. See the [AI Disclosure](https://snipfit.app/legal/ai-disclosure).

## Retention and deletion policy

| Data | Retention |
|---|---|
| Face landmarks, segmentation maps | Not retained: memory only, discarded immediately |
| Photos and cutouts on your phone | Until you delete them in the app or uninstall it |
| AI try-on inputs on our servers | Deleted within 24 hours |

## Your choices

You can withdraw consent at any time in **Settings → Face processing on this phone**. New face processing then stops; you can delete existing photos in **Settings → Delete photos on this phone**.

Questions: [privacy@snipfit.app](mailto:privacy@snipfit.app).

# Share kits

The share sheet has big buttons for Instagram Stories, TikTok, Snapchat and WhatsApp, plus More (system sheet). Native code lives in `ios/Runner/ShareTargets.swift` and `android/app/src/main/kotlin/com/snipfit/app/ShareTargets.kt`; when a target can't be used, Dart falls back to the system share sheet, and the caption plus invite link are always on the clipboard.

| Target | Today | To finish |
|---|---|---|
| Instagram Stories | Meta's official Stories sharing: pasteboard + `instagram-stories://` on iOS, `com.instagram.share.ADD_TO_STORY` intent on Android | Create a Meta app, put its App ID in `FACEBOOK_APP_ID` |
| TikTok | Android: targeted share intent to the TikTok app. iOS: system sheet | Register for TikTok **Share Kit**, add the SDK (iOS: TikTokOpenShareSDK via SPM; Android: `com.tiktok.open.sdk:tiktok-open-sdk-share`), put the client key in `TIKTOK_CLIENT_KEY`, then call the kit from `ShareTargets` for `tiktok` |
| Snapchat | Android: targeted share intent. iOS: system sheet | Register for Snap **Creative Kit**, add the SDK, put the client ID in `SNAP_CLIENT_ID`, call the kit for `snapchat` |
| WhatsApp | Android: targeted share intent. iOS: system sheet (WhatsApp is listed there) | Nothing required |

Rules kept by the code: sharing is never required for any feature or reward, every free export carries the small "Made with Snipfit" mark (removed for Pro) away from the face and the fabric, exports never contain location or camera metadata, and photos of someone else show a reminder to share only with their permission.

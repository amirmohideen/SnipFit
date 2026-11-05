import UIKit

/// Direct sharing to one app.
///
/// Instagram Stories uses Meta's documented pasteboard + URL scheme flow
/// (needs the Facebook App ID). TikTok's Share Kit and Snapchat's Creative
/// Kit are SDKs that need their own developer registration and app IDs; until
/// they're added (docs/SHARE_KITS.md) those targets return false and Dart uses
/// the system share sheet, which lists TikTok, Snapchat and WhatsApp.
final class ShareTargets {
  private let schemes = [
    "instagram": "instagram-stories://",
    "tiktok": "tiktok://",
    "snapchat": "snapchat://",
    "whatsapp": "whatsapp://",
  ]

  func isInstalled(_ target: String) -> Bool {
    guard let s = schemes[target], let url = URL(string: s) else { return false }
    return UIApplication.shared.canOpenURL(url)
  }

  func shareTo(target: String, path: String, mimeType: String, appIds: [String: String]) -> Bool {
    switch target {
    case "instagram":
      guard let appId = appIds["facebook"], !appId.isEmpty,
        let url = URL(string: "instagram-stories://share?source_application=\(appId)"),
        UIApplication.shared.canOpenURL(url),
        let data = try? Data(contentsOf: URL(fileURLWithPath: path))
      else { return false }
      let key = mimeType.hasPrefix("video")
        ? "com.instagram.sharedSticker.backgroundVideo"
        : "com.instagram.sharedSticker.backgroundImage"
      UIPasteboard.general.setItems(
        [[key: data]],
        options: [.expirationDate: Date().addingTimeInterval(5 * 60)])
      UIApplication.shared.open(url)
      return true
    default:
      return false
    }
  }
}

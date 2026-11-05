import Flutter
import UIKit

/// Snipfit's own platform channels (see lib/core/platform/native_channels.dart).
/// Heavy work runs on background queues; replies are delivered on the main queue.
enum SnipfitChannels {
  private static let videoQueue = DispatchQueue(label: "app.snipfit.video")
  private static let visionQueue = DispatchQueue(label: "app.snipfit.vision", qos: .userInitiated)
  private static var encoder: VideoEncoder?
  private static let share = ShareTargets()
  private static let tapSegmenter = TapSegmenter()

  static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()

    FlutterMethodChannel(name: "snipfit/platform", binaryMessenger: messenger).setMethodCallHandler { call, result in
      switch call.method {
      case "excludeFromBackup":
        guard let path = (call.arguments as? [String: Any])?["path"] as? String else {
          return result(FlutterError(code: "bad_args", message: "path required", details: nil))
        }
        // Private photos and windows must never reach iCloud/device backups.
        var url = URL(fileURLWithPath: path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
          try url.setResourceValues(values)
          result(nil)
        } catch {
          result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    FlutterMethodChannel(name: "snipfit/video", binaryMessenger: messenger).setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "start":
        videoQueue.async {
          encoder?.cancel()
          do {
            encoder = try VideoEncoder(
              path: args["path"] as? String ?? "",
              width: args["width"] as? Int ?? 720,
              height: args["height"] as? Int ?? 1280,
              fps: args["fps"] as? Int ?? 30,
              bitrate: args["bitrate"] as? Int ?? 6_000_000
            )
            DispatchQueue.main.async { result(true) }
          } catch {
            encoder = nil
            DispatchQueue.main.async { result(false) }
          }
        }
      case "addFrame":
        guard let data = (args["rgba"] as? FlutterStandardTypedData)?.data else {
          return result(FlutterError(code: "bad_args", message: "rgba required", details: nil))
        }
        videoQueue.async {
          do {
            try encoder?.append(rgba: data)
            DispatchQueue.main.async { result(nil) }
          } catch {
            DispatchQueue.main.async { result(FlutterError(code: "encode_failed", message: error.localizedDescription, details: nil)) }
          }
        }
      case "finish":
        videoQueue.async {
          guard let current = encoder else {
            DispatchQueue.main.async { result(false) }
            return
          }
          current.finish { ok in
            encoder = nil
            DispatchQueue.main.async { result(ok) }
          }
        }
      case "cancel":
        videoQueue.async {
          encoder?.cancel()
          encoder = nil
          DispatchQueue.main.async { result(nil) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    FlutterMethodChannel(name: "snipfit/share", binaryMessenger: messenger).setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "isInstalled":
        result(share.isInstalled(args["target"] as? String ?? ""))
      case "shareTo":
        result(
          share.shareTo(
            target: args["target"] as? String ?? "",
            path: args["path"] as? String ?? "",
            mimeType: args["mimeType"] as? String ?? "image/jpeg",
            appIds: args["appIds"] as? [String: String] ?? [:]
          ))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    FlutterMethodChannel(name: "snipfit/tap_segmenter", binaryMessenger: messenger).setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "isAvailable":
        result(TapSegmenter.isAvailable)
      case "segment":
        let path = args["path"] as? String ?? ""
        let x = args["x"] as? Double ?? 0.5
        let y = args["y"] as? Double ?? 0.5
        visionQueue.async {
          do {
            let png = try tapSegmenter.segment(path: path, x: x, y: y)
            DispatchQueue.main.async { result(png.map { FlutterStandardTypedData(bytes: $0) }) }
          } catch {
            DispatchQueue.main.async { result(FlutterError(code: "segment_failed", message: error.localizedDescription, details: nil)) }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

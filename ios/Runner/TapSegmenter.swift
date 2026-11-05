import CoreImage
import UIKit
import Vision

/// Tap-to-select garment on iOS 17+: Vision's foreground instance mask, picking
/// the instance under the tapped point. Runs on the device. Returns a
/// grayscale PNG mask the size of the (upright) photo.
final class TapSegmenter {
  enum SegmentError: Error { case unreadableImage }

  static var isAvailable: Bool {
    if #available(iOS 17.0, *) { return true }
    return false
  }

  private let context = CIContext()

  func segment(path: String, x: Double, y: Double) throws -> Data? {
    guard #available(iOS 17.0, *) else { return nil }
    guard let image = UIImage(contentsOfFile: path), let cg = image.cgImage else {
      throw SegmentError.unreadableImage
    }
    let handler = VNImageRequestHandler(cgImage: cg, orientation: CGImagePropertyOrientation(image.imageOrientation))
    let request = VNGenerateForegroundInstanceMaskRequest()
    try handler.perform([request])
    guard let observation = request.results?.first else { return nil }

    // Instance label under the tap (0 is background).
    let labels = observation.instanceMask
    CVPixelBufferLockBaseAddress(labels, .readOnly)
    let w = CVPixelBufferGetWidth(labels)
    let h = CVPixelBufferGetHeight(labels)
    let rowBytes = CVPixelBufferGetBytesPerRow(labels)
    let px = min(max(Int(x * Double(w - 1)), 0), w - 1)
    let py = min(max(Int(y * Double(h - 1)), 0), h - 1)
    let label = CVPixelBufferGetBaseAddress(labels)!.load(fromByteOffset: py * rowBytes + px, as: UInt8.self)
    CVPixelBufferUnlockBaseAddress(labels, .readOnly)
    guard label != 0 else { return nil }

    let scaled = try observation.generateScaledMaskForImage(forInstances: IndexSet(integer: Int(label)), from: handler)
    let mask = CIImage(cvPixelBuffer: scaled)
    guard let gray = context.createCGImage(mask, from: mask.extent, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
    else { return nil }
    return UIImage(cgImage: gray).pngData()
  }
}

extension CGImagePropertyOrientation {
  init(_ o: UIImage.Orientation) {
    switch o {
    case .up: self = .up
    case .upMirrored: self = .upMirrored
    case .down: self = .down
    case .downMirrored: self = .downMirrored
    case .left: self = .left
    case .leftMirrored: self = .leftMirrored
    case .right: self = .right
    case .rightMirrored: self = .rightMirrored
    @unknown default: self = .up
    }
  }
}

import AVFoundation
import Accelerate
import CoreVideo

/// H.264 MP4 encoder for the reveal video. RGBA frames come from Dart; no
/// location or device metadata is written into the file.
final class VideoEncoder {
  enum EncoderError: Error { case setupFailed, noPool, bufferFailed }

  private let writer: AVAssetWriter
  private let input: AVAssetWriterInput
  private let adaptor: AVAssetWriterInputPixelBufferAdaptor
  private let width: Int
  private let height: Int
  private let fps: Int32
  private let url: URL
  private var frame: Int64 = 0

  init(path: String, width: Int, height: Int, fps: Int, bitrate: Int) throws {
    self.width = width
    self.height = height
    self.fps = Int32(fps)
    url = URL(fileURLWithPath: path)
    try? FileManager.default.removeItem(at: url)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    writer.metadata = []
    input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [
          AVVideoAverageBitRateKey: bitrate,
          AVVideoExpectedSourceFrameRateKey: fps,
          AVVideoMaxKeyFrameIntervalKey: fps,
        ],
      ])
    input.expectsMediaDataInRealTime = false
    adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
      ])
    guard writer.canAdd(input) else { throw EncoderError.setupFailed }
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? EncoderError.setupFailed }
    writer.startSession(atSourceTime: .zero)
  }

  func append(rgba: Data) throws {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
    guard let pool = adaptor.pixelBufferPool else { throw EncoderError.noPool }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
    guard let pb = buffer else { throw EncoderError.bufferFailed }
    CVPixelBufferLockBaseAddress(pb, [])
    defer { CVPixelBufferUnlockBaseAddress(pb, []) }
    guard let base = CVPixelBufferGetBaseAddress(pb) else { throw EncoderError.bufferFailed }
    let destRowBytes = CVPixelBufferGetBytesPerRow(pb)
    rgba.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      var src = vImage_Buffer(
        data: UnsafeMutableRawPointer(mutating: raw.baseAddress!),
        height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * 4)
      var dst = vImage_Buffer(
        data: base, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: destRowBytes)
      // RGBA -> BGRA
      let map: [UInt8] = [2, 1, 0, 3]
      vImagePermuteChannels_ARGB8888(&src, &dst, map, vImage_Flags(kvImageNoFlags))
    }
    adaptor.append(pb, withPresentationTime: CMTime(value: frame, timescale: fps))
    frame += 1
  }

  func finish(_ completion: @escaping (Bool) -> Void) {
    input.markAsFinished()
    writer.finishWriting { [writer] in completion(writer.status == .completed) }
  }

  func cancel() {
    if writer.status == .writing { writer.cancelWriting() }
    try? FileManager.default.removeItem(at: url)
  }
}

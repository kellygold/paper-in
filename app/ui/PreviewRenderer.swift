import AppKit
import ImageIO

/// CGImage is immutable; AppKit wrappers are created only on the main thread.
final class PreviewBitmap: @unchecked Sendable {
  let image: CGImage
  init(_ image: CGImage) { self.image = image }
}

/// Screen images are bounded and cached independently of full-resolution PDF export.
final class PreviewRenderer: @unchecked Sendable {
  static let shared = PreviewRenderer()
  private let queue = DispatchQueue(label: "paper.preview", qos: .userInitiated)
  private let cache = NSCache<NSString, PreviewBitmap>()
  init() {
    cache.totalCostLimit = 64 * 1024 * 1024
    cache.countLimit = 80
  }
  static func key(folder: URL, page: StoredPage, pixels: Int) -> String {
    "\(folder.path)/\(page.source)/\(page.frame)/\(page.rotation)/\(pixels)/\(String(describing: page.crop))"
  }
  func image(folder: URL, page: StoredPage, pixels: Int) async throws -> PreviewBitmap {
    try Task.checkCancellation()
    let key = Self.key(folder: folder, page: page, pixels: pixels)
    if let cached = cache.object(forKey: key as NSString) { return cached }
    let image: PreviewBitmap = try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        if let cached = cache.object(forKey: key as NSString) {
          continuation.resume(returning: cached)
          return
        }
        let url = folder.appendingPathComponent("sources/\(page.source)")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let bitmap = CGImageSourceCreateThumbnailAtIndex(
            source, page.frame,
            [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceCreateThumbnailWithTransform: true,
              kCGImageSourceThumbnailMaxPixelSize: pixels,
            ] as CFDictionary)
        else {
          continuation.resume(throwing: PaperError("A saved page could not be opened."))
          return
        }
        var cropped = AutoCrop.apply(page.crop, to: bitmap)
        let rotation = ((page.rotation % 360) + 360) % 360
        if rotation != 0 {
          let swapped = rotation == 90 || rotation == 270
          let width = swapped ? cropped.height : cropped.width
          let height = swapped ? cropped.width : cropped.height
          if let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
          {
            context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
            context.rotate(by: -CGFloat(rotation) * .pi / 180)
            context.draw(
              cropped,
              in: CGRect(
                x: -CGFloat(cropped.width) / 2,
                y: -CGFloat(cropped.height) / 2, width: CGFloat(cropped.width),
                height: CGFloat(cropped.height)))
            if let rotated = context.makeImage() { cropped = rotated }
          }
        }
        let result = PreviewBitmap(cropped)
        cache.setObject(result, forKey: key as NSString, cost: cropped.bytesPerRow * cropped.height)
        continuation.resume(returning: result)
      }
    }
    try Task.checkCancellation()
    return image
  }
}

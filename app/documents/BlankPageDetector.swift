import CoreGraphics
import Foundation

/// Conservative, local blank-paper detection. Uncertain images are kept.
/// The caller retains original bytes and makes skipping a reversible draft edit.
enum BlankPageDetector {
  static func isClearlyBlank(_ image: CGImage) -> Bool {
    let scale = min(1, 1600.0 / Double(max(image.width, image.height)))
    let w = Int(Double(image.width) * scale)
    let h = Int(Double(image.height) * scale)
    guard w >= 100, h >= 100 else { return false }
    var pixels = [UInt8](repeating: 255, count: w * h * 4)
    let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
      guard
        let ctx = CGContext(
          data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      ctx.setFillColor(CGColor(gray: 1, alpha: 1))
      ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
      ctx.interpolationQuality = .high
      ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
      return true
    }
    guard rendered else { return false }
    var histograms = Array(repeating: [Int](repeating: 0, count: 256), count: 3)
    for i in 0..<(w * h) {
      for channel in 0..<3 { histograms[channel][Int(pixels[i * 4 + channel])] += 1 }
    }
    let background = histograms.map { histogram -> Int in
      var count = 0
      for value in 0..<256 {
        count += histogram[value]
        if count >= w * h * 4 / 5 { return value }
      }
      return 255
    }
    // Dark/coloured paper and uncertain exposure aren't treated as blank.
    guard background.min()! >= 225, background.max()! - background.min()! <= 12 else {
      return false
    }
    var mask = [UInt8](repeating: 0, count: w * h)
    var strongCount = 0
    var faintCount = 0
    for i in mask.indices {
      let offset = i * 4
      let contrast = max(
        abs(background[0] - Int(pixels[offset])),
        max(
          abs(background[1] - Int(pixels[offset + 1])), abs(background[2] - Int(pixels[offset + 2]))
        ))
      if contrast >= 7 {
        mask[i] = contrast >= 22 ? 2 : 1
        faintCount += 1
        if mask[i] == 2 { strongCount += 1 }
      }
    }
    // Scattered content matters too: do not ignore sparse text or dotted marks.
    guard strongCount < 30, faintCount < 200 else { return false }
    var queue: [Int] = []
    for seed in mask.indices where mask[seed] != 0 {
      queue = [seed]
      var strong = mask[seed] == 2 ? 1 : 0
      mask[seed] = 0
      var next = 0
      while next < queue.count {
        let p = queue[next]
        next += 1
        let x = p % w
        let y = p / w
        for dy in -1...1 {
          for dx in -1...1 where dx != 0 || dy != 0 {
            let nx = x + dx
            let ny = y + dy
            guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
            let neighbor = ny * w + nx
            guard mask[neighbor] != 0 else { continue }
            if mask[neighbor] == 2 { strong += 1 }
            mask[neighbor] = 0
            queue.append(neighbor)
          }
        }
        // Connected dark ink or faint strokes override the blank decision.
        if strong >= 5 || queue.count >= 24 { return false }
      }
    }
    return true
  }
}

import CoreGraphics
import Foundation

/// A second pass for a physical item located on a known scanner background.
/// Global ink counts mistake curled edges, soft folds and show-through for ink.
/// Analyse the paper silhouette and local stroke detail without altering its image.
enum ShadowedPaperDetector {
  static func isBlank(_ image: CGImage, scannerBackground: [[Int]]) -> Bool {
    let colors = scannerBackground.filter { $0.count == 3 }
    guard !colors.isEmpty else { return false }
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
      ctx.interpolationQuality = .high
      ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
      return true
    }
    guard rendered else { return false }
    let count = w * h
    var histogram = [Int](repeating: 0, count: 256)
    var luminance = [Double](repeating: 0, count: count)
    var spread = [Int](repeating: 0, count: count)
    var knownBackground = [Bool](repeating: false, count: count)
    for p in 0..<count {
      let r = Int(pixels[p * 4])
      let g = Int(pixels[p * 4 + 1])
      let b = Int(pixels[p * 4 + 2])
      let low = min(r, min(g, b))
      let high = max(r, max(g, b))
      luminance[p] = Double(low)
      histogram[low] += 1
      spread[p] = high - low
      knownBackground[p] =
        low >= 45 && high <= 240 && spread[p] <= 32
        && colors.contains { abs($0[0] - r) <= 32 && abs($0[1] - g) <= 32 && abs($0[2] - b) <= 32 }
    }
    var cumulative = 0
    var background = 255
    for value in 0..<256 {
      cumulative += histogram[value]
      if cumulative >= count * 4 / 5 {
        background = value
        break
      }
    }
    guard background >= 240 else { return false }
    let contrast = luminance.map { abs(Double(background) - $0) }
    let rim = scannerRim(
      contrast: contrast, spread: spread, known: knownBackground, width: w, height: h)
    var paperCount = 0
    var shadowCount = 0
    var darkCount = 0
    for p in 0..<count {
      if rim[p] {
        luminance[p] = Double(background)
      } else {
        paperCount += 1
        if contrast[p] >= 7 { shadowCount += 1 }
        if contrast[p] >= 100 || spread[p] > 20 { darkCount += 1 }
      }
    }
    // Only use the more tolerant texture pass on broadly shadowed bright paper.
    // A sparse faint annotation on otherwise clean paper stays with the strict detector.
    guard paperCount >= count / 2, shadowCount >= paperCount / 200,
      shadowCount <= paperCount / 8, darkCount < 30
    else { return false }
    let smooth = boxBlur(luminance, width: w, height: h)
    let softer = boxBlur(smooth, width: w, height: h)
    var marks = [UInt8](repeating: 0, count: count)
    var faintStrokes = [UInt8](repeating: 0, count: count)
    var paleStrokes = faintStrokes
    var sharpCount = 0
    for p in 0..<count where !rim[p] {
      let detail = abs(smooth[p] - softer[p])
      // Protect coloured marks, while tolerating isolated colour noise.
      if contrast[p] >= 100 || spread[p] > 20 {
        marks[p] = 2
      } else if contrast[p] >= 7 && detail >= 5 {
        marks[p] = 1
      }
      if marks[p] != 0 { sharpCount += 1 }
      // Relative detail also protects connected pale strokes. Random paper grain
      // can supply many isolated pixels, but must not form a writing-sized stroke.
      if contrast[p] >= 7 && contrast[p] < 22 && detail >= 1 && detail >= contrast[p] / 10 {
        faintStrokes[p] = 1
      }
      // Downsampling can reduce a pale pencil line below the strict contrast
      // threshold. Still protect extended strokes at this near-noise level.
      if contrast[p] >= 3 && contrast[p] < 22 && detail >= 0.4 && detail >= contrast[p] / 10 {
        paleStrokes[p] = 1
      }
    }
    guard sharpCount < 200 else { return false }
    return !hasStroke(&marks, width: w, height: h)
      && !hasStroke(&faintStrokes, width: w, height: h)
      && !hasStroke(&paleStrokes, width: w, height: h, minimumExtent: 32)
  }

  /// Follow a supported neutral rim; do not discard a fixed page margin. Median
  /// neighbours bridge the tiny gaps where a crease meets the paper's edge.
  private static func scannerRim(
    contrast: [Double], spread: [Int], known: [Bool], width w: Int, height h: Int
  ) -> [Bool] {
    var rim = [Bool](repeating: false, count: w * h)
    for vertical in [true, false] {
      let length = vertical ? h : w
      let depth = vertical ? w : h
      let limit = max(1, depth * 15 / 100)
      for far in [false, true] {
        func index(_ along: Int, _ step: Int) -> Int {
          let across = far ? depth - 1 - step : step
          return vertical ? along * w + across : across * w + along
        }
        var ends = [Int](repeating: -1, count: length)
        var supported = 0
        var graySupport = 0
        for along in 0..<length {
          var start: Int?
          for step in 0..<min(4, limit) {
            let p = index(along, step)
            if contrast[p] >= 7 && spread[p] <= 32 {
              start = step
              break
            }
          }
          guard var end = start else { continue }
          var gray = false
          while end < limit {
            let p = index(along, end)
            guard contrast[p] >= 7 && spread[p] <= 32 else { break }
            gray = gray || known[p]
            end += 1
          }
          ends[along] = end
          supported += 1
          if gray { graySupport += 1 }
        }
        // Dark hairline shadows can join a gray rim. A standalone black printed
        // rule has no known scanner gray and is never accepted as that rim.
        guard supported >= length / 4, graySupport >= length / 8 else { continue }
        let radius = max(3, length / 50)
        for along in 0..<length {
          let neighbors = ends[max(0, along - radius)...min(length - 1, along + radius)]
          let usable = neighbors.filter { $0 >= 0 && $0 < limit }.sorted()
          guard usable.count >= 3 else { continue }
          let end = min(depth, usable[usable.count / 2] + 2)
          for step in 0..<end { rim[index(along, step)] = true }
        }
      }
    }
    return rim
  }

  private static func boxBlur(_ input: [Double], width w: Int, height h: Int) -> [Double] {
    var horizontal = [Double](repeating: 0, count: input.count)
    for y in 0..<h {
      for x in 0..<w {
        let p = y * w + x
        horizontal[p] =
          (input[y * w + max(0, x - 1)] + input[p]
            + input[y * w + min(w - 1, x + 1)]) / 3
      }
    }
    var output = horizontal
    for y in 0..<h {
      for x in 0..<w {
        let p = y * w + x
        output[p] =
          (horizontal[max(0, y - 1) * w + x] + horizontal[p]
            + horizontal[min(h - 1, y + 1) * w + x]) / 3
      }
    }
    return output
  }

  private static func hasStroke(
    _ mask: inout [UInt8], width w: Int, height h: Int, minimumExtent: Int = 0
  ) -> Bool {
    var queue: [Int] = []
    for seed in mask.indices where mask[seed] != 0 {
      queue.removeAll(keepingCapacity: true)
      queue.append(seed)
      var dark = mask[seed] == 2 ? 1 : 0
      mask[seed] = 0
      var next = 0
      var minX = seed % w
      var maxX = seed % w
      var minY = seed / w
      var maxY = seed / w
      while next < queue.count {
        let p = queue[next]
        next += 1
        minX = min(minX, p % w)
        maxX = max(maxX, p % w)
        minY = min(minY, p / w)
        maxY = max(maxY, p / w)
        for dy in -1...1 {
          for dx in -1...1 where dx != 0 || dy != 0 {
            let x = p % w + dx
            let y = p / w + dy
            guard x >= 0, y >= 0, x < w, y < h else { continue }
            let neighbor = y * w + x
            guard mask[neighbor] != 0 else { continue }
            if mask[neighbor] == 2 { dark += 1 }
            mask[neighbor] = 0
            queue.append(neighbor)
          }
        }
        if dark >= 5 || queue.count >= 100
          || (queue.count >= 24 && max(maxX - minX, maxY - minY) >= minimumExtent)
        {
          return true
        }
      }
    }
    return false
  }
}

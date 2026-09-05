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
    suppressScannerEdges(&mask, pixels: pixels, width: w, height: h)
    suppressFoldLines(&mask, pixels: pixels, background: background, width: w, height: h)
    strongCount = mask.reduce(0) { $0 + ($1 == 2 ? 1 : 0) }
    faintCount = mask.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
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

  /// Only remove neutral edge-connected runs spanning most of an image edge.
  /// A short mark at the edge is still content. Never trim a fixed margin.
  private static func suppressScannerEdges(
    _ mask: inout [UInt8], pixels: [UInt8], width w: Int, height h: Int
  ) {
    let original = mask
    for vertical in [true, false] {
      let length = vertical ? h : w
      let depth = vertical ? w : h
      let limit = max(1, depth / 25)
      for far in [false, true] {
        var runs = [Int](repeating: 0, count: length)
        var graySupport = 0
        for along in 0..<length {
          var hasGray = false
          for step in 0..<limit {
            let across = far ? depth - 1 - step : step
            let p = vertical ? along * w + across : across * w + along
            let rgb = (0..<3).map { Int(pixels[p * 4 + $0]) }
            guard original[p] != 0, rgb.max()! - rgb.min()! <= 32 else { break }
            if rgb.min()! >= 45 && rgb.max()! <= 230 { hasGray = true }
            runs[along] = step + 1
          }
          if hasGray { graySupport += 1 }
        }
        // An actual scanner edge is almost continuous over the sheet dimension.
        guard runs.filter({ $0 > 0 }).count >= length * 3 / 4, graySupport >= length / 2 else {
          continue
        }
        let smoothed = (0..<length).map { i -> Int in
          let neighbors = Array(runs[max(0, i - 3)...min(length - 1, i + 3)]).sorted()
          return neighbors[neighbors.count / 2]
        }
        for along in 0..<length {
          let run = smoothed[along] > 0 ? min(limit, smoothed[along] + 1) : 0
          for step in 0..<run {
            let across = far ? depth - 1 - step : step
            let p = vertical ? along * w + across : across * w + along
            mask[p] = 0
          }
        }
      }
    }
  }

  /// A faint crease forms a very thin, near-horizontal/vertical band across the
  /// sheet. Require broad support and cap both thickness and contrast so text,
  /// short handwriting and printed rules remain content.
  private static func suppressFoldLines(
    _ mask: inout [UInt8], pixels: [UInt8], background: [Int], width w: Int, height h: Int
  ) {
    for vertical in [false, true] {
      let length = vertical ? h : w
      let depth = vertical ? w : h
      let radius = max(3, depth / 100)
      var counts = [Int](repeating: 0, count: depth)
      for across in 0..<depth {
        for along in 0..<length {
          let p = vertical ? along * w + across : across * w + along
          if mask[p] != 0 { counts[across] += 1 }
        }
      }
      var candidates: [Int] = []
      for center in radius..<(depth - radius) where counts[center] > 0 {
        let sum = counts[(center - radius)...(center + radius)].reduce(0, +)
        if sum >= length / 2 { candidates.append(center) }
      }
      // A handful of folds is plausible; a page of ruled lines is content.
      var bands: [ClosedRange<Int>] = []
      for center in candidates {
        let band = (center - radius)...(center + radius)
        if let last = bands.last, band.lowerBound <= last.upperBound {
          bands[bands.count - 1] = last.lowerBound...max(last.upperBound, band.upperBound)
        } else {
          bands.append(band)
        }
      }
      guard bands.count <= 3 else { continue }
      for band in bands {
        guard band.count <= radius * 5 + 1 else { continue }
        var support = 0
        var total = 0
        var contrastSum = 0
        var peak = 0
        var thickColumns = 0
        var veryThickColumns = 0
        var members: [Int] = []
        var colored = 0
        for along in 0..<length {
          var occupied: [Int] = []
          for across in band {
            let p = vertical ? along * w + across : across * w + along
            guard mask[p] != 0 else { continue }
            let rgb = (0..<3).map { Int(pixels[p * 4 + $0]) }
            if rgb.max()! - rgb.min()! > 32 { colored += 1 }
            let contrast = (0..<3).map { abs(background[$0] - rgb[$0]) }.max()!
            peak = max(peak, contrast)
            contrastSum += contrast
            total += 1
            occupied.append(across)
            members.append(p)
          }
          if let first = occupied.first, let last = occupied.last {
            support += 1
            if last - first + 1 > max(12, depth / 80) { veryThickColumns += 1 }
            if last - first + 1 > max(5, depth / 200) { thickColumns += 1 }
          }
        }
        guard colored <= 3, support >= length * 9 / 20, total > 0,
          peak <= 120, contrastSum / total <= 40,
          thickColumns <= length / 20, veryThickColumns <= max(3, length / 80)
        else { continue }
        for p in members { mask[p] = 0 }
      }
    }
  }
}

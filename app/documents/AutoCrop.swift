import CoreGraphics
import Foundation

// Coordinates are fractions of the EXIF-oriented image, measured from its top left.
// Only metadata is stored; the original scanner image is never rewritten.
struct PageCrop: Codable, Equatable {
  var x: Double
  var y: Double
  var width: Double
  var height: Double
  var scannerBackground: [[Int]]? = nil
  func rectangle(in image: CGImage) -> CGRect {
    CGRect(
      x: x * Double(image.width), y: y * Double(image.height), width: width * Double(image.width),
      height: height * Double(image.height)
    ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
  }
}
enum AutoCrop {
  static func detect(_ image: CGImage) -> PageCrop? {
    var current = image
    var bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    var changed = false
    var backgrounds: [[Int]] = []
    // The device pads beyond the paper with a different grey from its roller background.
    // First remove that padding, then locate the physical item within the remaining strip.
    for _ in 0..<3 {
      guard let next = detectRim(current) ?? detectOnce(current) else { break }
      let rect = next.rectangle(in: current)
      backgrounds += next.scannerBackground ?? []
      if rect.width == CGFloat(current.width) && rect.height == CGFloat(current.height) {
        changed = !backgrounds.isEmpty || changed
        break
      }
      guard let cropped = current.cropping(to: rect),
        rect.width < CGFloat(current.width) || rect.height < CGFloat(current.height)
      else { break }
      bounds = CGRect(
        x: bounds.minX + rect.minX, y: bounds.minY + rect.minY, width: rect.width,
        height: rect.height)
      current = cropped
      changed = true
    }
    guard changed else { return nil }
    return PageCrop(
      x: bounds.minX / Double(image.width), y: bounds.minY / Double(image.height),
      width: bounds.width / Double(image.width), height: bounds.height / Double(image.height),
      scannerBackground: backgrounds.isEmpty ? nil : backgrounds)
  }
  // A nearly full-size sheet can have a grey rim on just one or two sides.
  // A median-of-all-borders background misses that case. Inspect each edge
  // independently and require a continuous neutral rim before trimming it.
  private static func detectRim(_ image: CGImage) -> PageCrop? {
    let scale = min(1, 900.0 / Double(max(image.width, image.height)))
    let w = Int(Double(image.width) * scale)
    let h = Int(Double(image.height) * scale)
    guard w >= 100, h >= 100 else { return nil }
    var pixels = [UInt8](repeating: 255, count: w * h * 4)
    let ok = pixels.withUnsafeMutableBytes { bytes -> Bool in
      guard
        let ctx = CGContext(
          data: bytes.baseAddress, width: w, height: h,
          bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      ctx.interpolationQuality = .high
      ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
      return true
    }
    guard ok else { return nil }
    // Only use this refinement on a predominantly bright sheet. Small items
    // on a scanner background continue through the physical-item detector.
    var white = 0
    for p in 0..<(w * h) {
      if min(pixels[p * 4], min(pixels[p * 4 + 1], pixels[p * 4 + 2])) >= 240 { white += 1 }
    }
    guard white >= w * h * 3 / 4 else { return nil }
    var backgrounds: [[Int]] = []
    func inset(vertical: Bool, far: Bool) -> Int {
      let length = vertical ? h : w
      let depth = vertical ? w : h
      let limit = max(1, depth / 25)
      var runs: [Int] = []
      var graySamples: [[Int]] = []
      var supported = 0
      for along in 0..<length {
        var run = 0
        var hasGray = false
        for step in 0..<limit {
          let across = far ? depth - 1 - step : step
          let p = vertical ? along * w + across : across * w + along
          let rgb = (0..<3).map { Int(pixels[p * 4 + $0]) }
          guard rgb.max()! <= 240, rgb.max()! - rgb.min()! <= 32 else { break }
          if rgb.min()! >= 45 && rgb.max()! <= 230 {
            hasGray = true
            graySamples.append(rgb)
          }
          run = step + 1
        }
        runs.append(run)
        if run > 0 && run < limit && hasGray { supported += 1 }
      }
      guard supported >= length * 3 / 4, !graySamples.isEmpty else { return 0 }
      backgrounds.append(
        (0..<3).map { c in graySamples.map { $0[c] }.sorted()[graySamples.count / 2] })
      // Keep the full physical paper extent. The residual slanted rim is
      // whitened outside the paper instead of cropping into the page.
      let sorted = runs.sorted()
      return max(0, (sorted.first ?? 0) - 1)
    }
    let left = inset(vertical: true, far: false)
    let right = inset(vertical: true, far: true)
    let top = inset(vertical: false, far: false)
    let bottom = inset(vertical: false, far: true)
    guard !backgrounds.isEmpty else { return nil }
    return PageCrop(
      x: Double(left) / Double(w), y: Double(top) / Double(h),
      width: Double(w - left - right) / Double(w), height: Double(h - top - bottom) / Double(h),
      scannerBackground: backgrounds)
  }
  private static func detectOnce(_ image: CGImage) -> PageCrop? {
    let scale = min(1, 900.0 / Double(max(image.width, image.height)))
    let w = max(1, Int(Double(image.width) * scale))
    let h = max(1, Int(Double(image.height) * scale))
    guard w >= 20, h >= 20 else { return nil }
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
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
    guard rendered else { return nil }
    var border: [[Int]] = [[], [], []]
    for y in stride(from: 0, to: h, by: 3) {
      for x in stride(from: 0, to: w, by: 3) where x < 4 || y < 4 || x >= w - 4 || y >= h - 4 {
        let i = (y * w + x) * 4
        for c in 0..<3 { border[c].append(Int(pixels[i + c])) }
      }
    }
    let background = border.map { values -> Int in
      let sorted = values.sorted()
      return sorted[sorted.count / 2]
    }
    // A white/full-frame sheet must not be cropped down to its printed text.
    // Unknown, very dark or strongly coloured backgrounds retain the full capture.
    guard background.min()! >= 45, background.max()! <= 235,
      background.max()! - background.min()! < 35
    else { return nil }
    // The padded area and visible rollers may have distinct neutral tones.
    // Accept a second background only when it occupies a substantial part of the border.
    var groups: [Int: [Int]] = [:]
    for i in border[0].indices {
      let color = (0..<3).map { border[$0][i] }
      let distance = (0..<3).map { abs(color[$0] - background[$0]) }.max()!
      if color.min()! >= 45 && color.max()! <= 235 && color.max()! - color.min()! < 35
        && distance > 28
      {
        groups[(color.reduce(0, +) / 3) / 16, default: []].append(i)
      }
    }
    var secondary: [Int]?
    if let samples = groups.values.max(by: { $0.count < $1.count }),
      samples.count >= border[0].count / 12
    {
      secondary = (0..<3).map { c in
        let values = samples.map { border[c][$0] }.sorted()
        return values[values.count / 2]
      }
    }
    var mask = [UInt8](repeating: 0, count: w * h)
    for i in 0..<(w * h) {
      let distance = (0..<3).map { abs(Int(pixels[i * 4 + $0]) - background[$0]) }.max()!
      let otherDistance =
        secondary.map { color in (0..<3).map { abs(Int(pixels[i * 4 + $0]) - color[$0]) }.max()! }
        ?? 255
      if distance > 28 && otherDistance > 28 { mask[i] = 1 }
    }
    struct Component {
      var count: Int
      var left: Int
      var top: Int
      var right: Int
      var bottom: Int
    }
    var components: [Component] = []
    var queue: [Int] = []
    queue.reserveCapacity(w * h)
    for seed in 0..<mask.count where mask[seed] == 1 {
      queue.removeAll(keepingCapacity: true)
      queue.append(seed)
      mask[seed] = 0
      var next = 0
      var part = Component(count: 0, left: w, top: h, right: 0, bottom: 0)
      while next < queue.count {
        let p = queue[next]
        next += 1
        let x = p % w
        let y = p / w
        part.count += 1
        part.left = min(part.left, x)
        part.right = max(part.right, x)
        part.top = min(part.top, y)
        part.bottom = max(part.bottom, y)
        for dy in -1...1 {
          for dx in -1...1 where dx != 0 || dy != 0 {
            let nx = x + dx
            let ny = y + dy
            if nx >= 0 && nx < w && ny >= 0 && ny < h {
              let n = ny * w + nx
              if mask[n] == 1 {
                mask[n] = 0
                queue.append(n)
              }
            }
          }
        }
      }
      if part.count >= 12 { components.append(part) }
    }
    guard let best = components.max(by: { $0.count < $1.count }) else { return nil }
    let bw = best.right - best.left + 1
    let bh = best.bottom - best.top + 1
    guard bw >= 12, bh >= 12, best.count > w * h / 250,
      Double(best.count) / Double(bw * bh) > 0.55,
      Double(bw * bh) / Double(w * h) < 0.96
    else { return nil }
    // Ambiguous separate substantial regions: keep everything rather than choosing one.
    for part in components where part.count > max(30, best.count / 20) {
      if part.left < best.left - 3 || part.right > best.right + 3 || part.top < best.top - 3
        || part.bottom > best.bottom + 3
      {
        return nil
      }
    }
    let left = max(0, best.left - 2)
    let top = max(0, best.top - 2)
    let right = min(w, best.right + 3)
    let bottom = min(h, best.bottom + 3)
    return PageCrop(
      x: Double(left) / Double(w), y: Double(top) / Double(h),
      width: Double(right - left) / Double(w), height: Double(bottom - top) / Double(h),
      scannerBackground: [background] + (secondary.map { [$0] } ?? []))
  }
  static func apply(_ crop: PageCrop?, to image: CGImage) -> CGImage {
    guard let crop else { return image }
    let rect = crop.rectangle(in: image)
    guard !rect.isNull, rect.width > 0, rect.height > 0 else { return image }
    let cropped = image.cropping(to: rect) ?? image
    return cleanRim(cropped, backgrounds: crop.scannerBackground ?? [])
  }
  private static func cleanRim(_ image: CGImage, backgrounds: [[Int]]) -> CGImage {
    let colors = backgrounds.filter { $0.count == 3 }
    guard !colors.isEmpty else { return image }
    let w = image.width
    let h = image.height
    var pixels = [UInt8](repeating: 255, count: w * h * 4)
    return pixels.withUnsafeMutableBytes { bytes -> CGImage in
      guard
        let ctx = CGContext(
          data: bytes.baseAddress, width: w, height: h,
          bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return image }
      ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
      let data = bytes.bindMemory(to: UInt8.self)
      var seen = [Bool](repeating: false, count: w * h)
      var queue: [Int] = []
      func add(_ x: Int, _ y: Int) {
        guard x >= 0, y >= 0, x < w, y < h,
          x < max(2, w / 25) || x >= w - max(2, w / 25) || y < max(2, h / 25)
            || y >= h - max(2, h / 25)
        else { return }
        let p = y * w + x
        guard !seen[p] else { return }
        seen[p] = true
        let rgb = (0..<3).map { Int(data[p * 4 + $0]) }
        guard rgb.min()! >= 45, rgb.max()! <= 240, rgb.max()! - rgb.min()! <= 32,
          colors.contains(where: { c in (0..<3).allSatisfy { abs(c[$0] - rgb[$0]) <= 32 } })
        else { return }
        queue.append(p)
      }
      for x in 0..<w {
        add(x, 0)
        add(x, h - 1)
      }
      for y in 0..<h {
        add(0, y)
        add(w - 1, y)
      }
      var next = 0
      while next < queue.count {
        let p = queue[next]
        next += 1
        for c in 0..<4 { data[p * 4 + c] = 255 }
        let x = p % w
        let y = p / w
        add(x - 1, y)
        add(x + 1, y)
        add(x, y - 1)
        add(x, y + 1)
      }
      return ctx.makeImage() ?? image
    }
  }

}

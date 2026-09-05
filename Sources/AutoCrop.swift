import Foundation
import CoreGraphics

// Coordinates are fractions of the EXIF-oriented image, measured from its top left.
// Only metadata is stored; the original scanner image is never rewritten.
struct PageCrop: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    func rectangle(in image: CGImage) -> CGRect {
        CGRect(x: x * Double(image.width), y: y * Double(image.height), width: width * Double(image.width), height: height * Double(image.height)).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
}
enum AutoCrop {
    static func detect(_ image: CGImage) -> PageCrop? {
        var current = image
        var bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        var changed = false
        // The device pads beyond the paper with a different grey from its roller background.
        // First remove that padding, then locate the physical item within the remaining strip.
        for _ in 0..<3 {
            guard let next = detectOnce(current) else { break }
            let rect = next.rectangle(in: current)
            guard let cropped = current.cropping(to: rect), rect.width < CGFloat(current.width) || rect.height < CGFloat(current.height) else { break }
            bounds = CGRect(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY, width: rect.width, height: rect.height)
            current = cropped; changed = true
        }
        guard changed else { return nil }
        return PageCrop(x: bounds.minX / Double(image.width), y: bounds.minY / Double(image.height), width: bounds.width / Double(image.width), height: bounds.height / Double(image.height))
    }
    private static func detectOnce(_ image: CGImage) -> PageCrop? {
        let scale = min(1, 900.0 / Double(max(image.width, image.height)))
        let w = max(1, Int(Double(image.width) * scale)), h = max(1, Int(Double(image.height) * scale))
        guard w >= 20, h >= 20 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let ctx = CGContext(data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h)); return true
        }
        guard rendered else { return nil }
        var border: [[Int]] = [[], [], []]
        for y in stride(from: 0, to: h, by: 3) {
            for x in stride(from: 0, to: w, by: 3) where x < 4 || y < 4 || x >= w - 4 || y >= h - 4 {
                let i = (y * w + x) * 4
                for c in 0..<3 { border[c].append(Int(pixels[i + c])) }
            }
        }
        let background = border.map { values -> Int in let sorted = values.sorted(); return sorted[sorted.count / 2] }
        // A white/full-frame sheet must not be cropped down to its printed text.
        // Unknown, very dark or strongly coloured backgrounds retain the full capture.
        guard background.min()! >= 45, background.max()! <= 235,
              background.max()! - background.min()! < 35 else { return nil }
        // The padded area and visible rollers may have distinct neutral tones.
        // Accept a second background only when it occupies a substantial part of the border.
        var groups: [Int: [Int]] = [:]
        for i in border[0].indices {
            let color = (0..<3).map { border[$0][i] }
            let distance = (0..<3).map { abs(color[$0] - background[$0]) }.max()!
            if color.min()! >= 45 && color.max()! <= 235 && color.max()! - color.min()! < 35 && distance > 28 {
                groups[(color.reduce(0,+) / 3) / 16, default: []].append(i)
            }
        }
        var secondary: [Int]?
        if let samples = groups.values.max(by: { $0.count < $1.count }), samples.count >= border[0].count / 12 {
            secondary = (0..<3).map { c in let values = samples.map { border[c][$0] }.sorted(); return values[values.count / 2] }
        }
        var mask = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let distance = (0..<3).map { abs(Int(pixels[i * 4 + $0]) - background[$0]) }.max()!
            let otherDistance = secondary.map { color in (0..<3).map { abs(Int(pixels[i * 4 + $0]) - color[$0]) }.max()! } ?? 255
            if distance > 28 && otherDistance > 28 { mask[i] = 1 }
        }
        struct Component { var count: Int; var left: Int; var top: Int; var right: Int; var bottom: Int }
        var components: [Component] = []
        var queue: [Int] = []; queue.reserveCapacity(w * h)
        for seed in 0..<mask.count where mask[seed] == 1 {
            queue.removeAll(keepingCapacity: true); queue.append(seed); mask[seed] = 0
            var next = 0
            var part = Component(count: 0, left: w, top: h, right: 0, bottom: 0)
            while next < queue.count {
                let p = queue[next]; next += 1; let x = p % w, y = p / w
                part.count += 1; part.left = min(part.left, x); part.right = max(part.right, x); part.top = min(part.top, y); part.bottom = max(part.bottom, y)
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        if nx >= 0 && nx < w && ny >= 0 && ny < h {
                            let n = ny * w + nx
                            if mask[n] == 1 { mask[n] = 0; queue.append(n) }
                        }
                    }
                }
            }
            if part.count >= 12 { components.append(part) }
        }
        guard let best = components.max(by: { $0.count < $1.count }) else { return nil }
        let bw = best.right - best.left + 1, bh = best.bottom - best.top + 1
        guard bw >= 12, bh >= 12, best.count > w * h / 250,
              Double(best.count) / Double(bw * bh) > 0.55,
              Double(bw * bh) / Double(w * h) < 0.96 else { return nil }
        // Ambiguous separate substantial regions: keep everything rather than choosing one.
        for part in components where part.count > max(30, best.count / 20) {
            if part.left < best.left - 3 || part.right > best.right + 3 || part.top < best.top - 3 || part.bottom > best.bottom + 3 { return nil }
        }
        let left = max(0, best.left - 2), top = max(0, best.top - 2)
        let right = min(w, best.right + 3), bottom = min(h, best.bottom + 3)
        return PageCrop(x: Double(left) / Double(w), y: Double(top) / Double(h), width: Double(right-left) / Double(w), height: Double(bottom-top) / Double(h))
    }
    static func apply(_ crop: PageCrop?, to image: CGImage) -> CGImage {
        guard let crop else { return image }
        let rect = crop.rectangle(in: image)
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return image }
        return image.cropping(to: rect) ?? image
    }
}

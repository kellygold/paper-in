import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager().createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  let context = NSGraphicsContext.current!.cgContext
  context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
  NSColor(calibratedRed: 0.12, green: 0.28, blue: 0.23, alpha: 1).setFill()
  NSBezierPath(
    roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 218, yRadius: 218
  ).fill()
  NSColor(calibratedRed: 0.80, green: 0.93, blue: 0.64, alpha: 1).setFill()
  NSBezierPath(
    roundedRect: NSRect(x: 300, y: 174, width: 452, height: 616), xRadius: 40, yRadius: 40
  ).fill()
  NSColor(calibratedRed: 0.98, green: 0.97, blue: 0.92, alpha: 1).setFill()
  NSBezierPath(
    roundedRect: NSRect(x: 234, y: 240, width: 452, height: 616), xRadius: 40, yRadius: 40
  ).fill()
  NSColor(calibratedRed: 0.12, green: 0.28, blue: 0.23, alpha: 1).setFill()
  for (y, width) in [(654, 264), (550, 264), (446, 166)] {
    NSBezierPath(
      roundedRect: NSRect(x: 326, y: y, width: width, height: 28), xRadius: 14, yRadius: 14
    ).fill()
  }
  NSGraphicsContext.restoreGraphicsState()
  let data = bitmap.representation(using: .png, properties: [:])!
  if size <= 512 && size != 64 {
    try data.write(to: destination.appendingPathComponent("icon_\(size)x\(size).png"))
  }
  if size >= 32 && size != 128 {
    let half = size / 2
    try data.write(to: destination.appendingPathComponent("icon_\(half)x\(half)@2x.png"))
  }
}

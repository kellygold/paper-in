import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

let fm = FileManager()
let root = fm.temporaryDirectory.appendingPathComponent("PaperIn-BlankPages-\(UUID())")
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }

func fixture(
  _ name: String, background: CGColor = CGColor(gray: 1, alpha: 1), width: Int = 1000,
  height: Int = 1400,
  draw: (CGContext) -> Void = { _ in }
) throws -> (URL, CGImage) {
  let ctx = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8,
    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.setFillColor(background)
  ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
  draw(ctx)
  let image = ctx.makeImage()!
  let url = root.appendingPathComponent(name + ".png")
  let target = CGImageDestinationCreateWithURL(
    url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(target, image, nil)
  precondition(CGImageDestinationFinalize(target))
  return (url, image)
}
let (blank, white) = try fixture("white")
precondition(BlankPageDetector.isClearlyBlank(white))
let (_, specks) = try fixture("specks") { ctx in
  ctx.setFillColor(CGColor(gray: 0, alpha: 1))
  for i in 0..<5 { ctx.fill(CGRect(x: 100 + i * 90, y: 500, width: 1, height: 1)) }
}
precondition(BlankPageDetector.isClearlyBlank(specks))
let (_, noise) = try fixture("noise", background: CGColor(gray: 250.0 / 255, alpha: 1)) { ctx in
  for y in stride(from: 0, to: 1400, by: 7) {
    ctx.setFillColor(CGColor(gray: 248.0 / 255, alpha: 1))
    ctx.fill(CGRect(x: 0, y: y, width: 1000, height: 1))
  }
}
precondition(BlankPageDetector.isClearlyBlank(noise))
print("PASS blank white paper, mild neutral noise and isolated dust specks are recognized")

let (ink, printed) = try fixture("ink") { ctx in
  ctx.setFillColor(CGColor(gray: 0, alpha: 1))
  ctx.fill(CGRect(x: 800, y: 20, width: 4, height: 9))  // Small page number/mark.
}
let (_, faint) = try fixture("faint") { ctx in
  ctx.setStrokeColor(CGColor(gray: 0.965, alpha: 1))
  ctx.setLineWidth(2)
  ctx.move(to: CGPoint(x: 100, y: 100))
  ctx.addCurve(
    to: CGPoint(x: 270, y: 120), control1: CGPoint(x: 130, y: 50), control2: CGPoint(x: 200, y: 220)
  )
  ctx.strokePath()
}
let (_, edge) = try fixture("edge") { ctx in
  ctx.setFillColor(CGColor(gray: 0, alpha: 1))
  ctx.fill(CGRect(x: 0, y: 200, width: 2, height: 30))
}
let (_, colouredInk) = try fixture("coloured-ink") { ctx in
  ctx.setFillColor(CGColor(red: 1, green: 1, blue: 0.7, alpha: 1))
  ctx.fill(CGRect(x: 300, y: 300, width: 30, height: 20))
}
let (_, lightInk) = try fixture("light-ink", background: CGColor(gray: 0.94, alpha: 1)) { ctx in
  ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
  ctx.setLineWidth(3)
  ctx.move(to: CGPoint(x: 100, y: 400))
  ctx.addLine(to: CGPoint(x: 300, y: 500))
  ctx.strokePath()
}
for image in [printed, faint, edge, colouredInk, lightInk] {
  precondition(!BlankPageDetector.isClearlyBlank(image), "Meaningful marks were hidden")
}
let (_, scanSizeFaint) = try fixture("scan-size-faint", width: 2550, height: 3508) { ctx in
  ctx.setStrokeColor(CGColor(gray: 0.965, alpha: 1))
  ctx.setLineWidth(4)
  ctx.move(to: CGPoint(x: 100, y: 200))
  ctx.addLine(to: CGPoint(x: 300, y: 250))
  ctx.strokePath()
}
precondition(
  !BlankPageDetector.isClearlyBlank(scanSizeFaint),
  "Faint ink disappeared during scanner-size downsampling")
print(
  "PASS tiny ink, faint strokes, edge content, coloured marks and lighter-than-paper ink are retained"
)

let (_, dark) = try fixture("dark", background: CGColor(gray: 0.6, alpha: 1))
let (_, coloured) = try fixture(
  "coloured", background: CGColor(red: 1, green: 0.96, blue: 0.8, alpha: 1))
precondition(!BlankPageDetector.isClearlyBlank(dark) && !BlankPageDetector.isClearlyBlank(coloured))
let tiny = white.cropping(to: CGRect(x: 0, y: 0, width: 40, height: 60))!
precondition(!BlankPageDetector.isClearlyBlank(tiny))
print("PASS dark/coloured backgrounds and undersized images remain uncertain and visible")

let store = try DraftStore(root: root.appendingPathComponent("store"))
try store.beginCapture(expectedSides: 2)
try store.ingest(blank, skipBlankBacks: true)  // Blank front must remain.
try store.ingest(blank, skipBlankBacks: true)
try store.completeCapture(success: true)
let front = store.draft.pages[0]
let back = store.draft.pages[1]
precondition(!front.removed && back.removed && back.blankBackSkipped == true)
precondition(front.side == 0 && back.side == 1 && front.sheetID == back.sheetID)
let originalBytes = try Data(contentsOf: blank)
let savedBytes = try Data(contentsOf: store.folder.appendingPathComponent("sources/" + back.source))
precondition(originalBytes == savedBytes)
let reloaded = try DraftStore(root: store.root)
precondition(reloaded.visiblePages.count == 1 && reloaded.draft.pages[1].blankBackSkipped == true)
let output = try reloaded.export(to: root.appendingPathComponent("output"))
precondition(PDFDocument(url: output)?.pageCount == 1)
print(
  "PASS only a known duplex back is skipped; originals, pairing, restart and PDF page count remain correct"
)

let restored = try DraftStore(root: root.appendingPathComponent("restored"))
try restored.beginCapture(expectedSides: 2)
try restored.ingest(ink, skipBlankBacks: true)
try restored.ingest(blank, skipBlankBacks: true)
try restored.completeCapture(success: true)
let backID = restored.draft.pages[1].id
let frontID = restored.draft.pages[0].id
try restored.remove(frontID)
precondition(restored.visiblePages.isEmpty)
try restored.restoreLastRemoved()
precondition(
  restored.visiblePages.map(\.id) == [frontID] && restored.draft.pages[1].blankBackSkipped == true)
try restored.restore(backID)
let resumed = try DraftStore(root: restored.root)
precondition(resumed.visiblePages.count == 2 && resumed.draft.pages[1].blankBackSkipped == nil)
try resumed.beginCapture(expectedSides: 2)
try resumed.ingest(ink, skipBlankBacks: true)
try resumed.ingest(ink, skipBlankBacks: true)
try resumed.completeCapture(success: true)
let restoredPDF = try resumed.export(to: root.appendingPathComponent("output"))
precondition(PDFDocument(url: restoredPDF)?.pageCount == 4)
print("PASS explicit restoration persists and later scans never re-hide a restored side")

let disabled = try DraftStore(root: root.appendingPathComponent("disabled"))
try disabled.beginCapture(expectedSides: 2)
try disabled.ingest(blank)
try disabled.ingest(blank)
try disabled.completeCapture(success: true)
try disabled.ingest(blank, skipBlankBacks: true)  // Unpaired import is not a known back.
try disabled.beginCapture(expectedSides: 1)
try disabled.ingest(blank, skipBlankBacks: true)
try disabled.completeCapture(success: true)
precondition(disabled.visiblePages.count == 4)
print("PASS disabled setting, legacy/unpaired imports and simplex pages retain every image")

let interrupted = try DraftStore(root: root.appendingPathComponent("interrupted"))
try interrupted.beginCapture(expectedSides: 2)
try interrupted.ingest(ink, skipBlankBacks: true)
interrupted.beforeWrite = { destination in
  if destination.lastPathComponent == "manifest.json" {
    throw PaperError("Injected manifest failure")
  }
}
do {
  try interrupted.ingest(blank, skipBlankBacks: true)
  fatalError("Manifest failure not injected")
} catch {}
let recovered = try DraftStore(root: interrupted.root)
precondition(recovered.draft.pages.count == 2 && recovered.visiblePages.count == 1)
precondition(recovered.draft.pages[1].blankBackSkipped == true && recovered.draft.interrupted)
try recovered.restoreLastRemoved()
precondition(recovered.visiblePages.count == 2)
print(
  "PASS interrupted ingestion recovers the skip decision and original side through the durable envelope"
)

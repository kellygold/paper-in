import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

let fm = FileManager()
let root = fm.temporaryDirectory.appendingPathComponent("PaperIn-Crop-" + UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
func expect(_ test: Bool, _ message: String) { precondition(test, message) }
func fixture(_ name: String, rect: CGRect?, whiteBackground: Bool = false, padded: Bool = false)
  throws -> URL
{
  let ctx = CGContext(
    data: nil, width: 1000, height: 1400, bitsPerComponent: 8, bytesPerRow: 4000,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.setFillColor(CGColor(gray: whiteBackground ? 1 : 0.7, alpha: 1))
  ctx.fill(CGRect(x: 0, y: 0, width: 1000, height: 1400))
  if padded {
    ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 1000, height: 1000))
  }
  if let rect {
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(rect)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fill(CGRect(x: rect.minX + 10, y: rect.minY + 15, width: rect.width - 20, height: 8))
  }
  if whiteBackground {
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fill(CGRect(x: 100, y: 100, width: 700, height: 15))
  }
  let url = root.appendingPathComponent(name + ".png")
  let dest = CGImageDestinationCreateWithURL(
    url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(
    dest, ctx.makeImage()!,
    [kCGImagePropertyDPIWidth: 300, kCGImagePropertyDPIHeight: 300] as CFDictionary)
  expect(CGImageDestinationFinalize(dest), "fixture failed")
  return url
}
let card = try fixture("card", rect: CGRect(x: 20, y: 1100, width: 400, height: 250))
let receipt = try fixture("receipt", rect: CGRect(x: 600, y: 50, width: 220, height: 1250))
let full = try fixture("full", rect: nil, whiteBackground: true)
let store = try DraftStore(root: root.appendingPathComponent("store"))
try store.ingest(card, autoCrop: true)
try store.ingest(receipt, autoCrop: true)
try store.ingest(full, autoCrop: true)
let pages = store.visiblePages
let cardImage = try store.image(for: pages[0])
let receiptImage = try store.image(for: pages[1])
expect(
  cardImage.width >= 400 && cardImage.width < 415 && cardImage.height >= 250
    && cardImage.height < 265, "Card border clipped or left on full page")
expect(
  receiptImage.width >= 220 && receiptImage.width < 235 && receiptImage.height >= 1250
    && receiptImage.height < 1265, "Receipt resized incorrectly")
expect(pages[2].crop == nil, "White sheet cropped down to its printing")
expect(
  try Data(contentsOf: card)
    == Data(contentsOf: store.folder.appendingPathComponent("sources/" + pages[0].source)),
  "Original rewritten")
try store.setAutoCrop(pages[0].id, enabled: false)
let restored = try DraftStore(root: store.root)
expect(
  try restored.image(for: restored.visiblePages[0]).width == 1000,
  "Full scan restore lost after restart")
try restored.cropUnreviewedPages()
expect(restored.visiblePages[0].crop == nil, "Migration reapplied a user-disabled crop")
try restored.setAutoCrop(pages[0].id, enabled: true)
let output = try restored.export(to: root.appendingPathComponent("output"))
let pdf = PDFDocument(url: output)!
expect(pdf.pageCount == 3, "PDF lost a page")
expect(pdf.page(at: 0)!.bounds(for: .mediaBox).width < 100, "Card PDF retained full paper width")
expect(pdf.page(at: 1)!.bounds(for: .mediaBox).height > 295, "Receipt PDF height was truncated")
expect(pdf.page(at: 2)!.bounds(for: .mediaBox).width == 240, "Full page dimensions changed")
print("PASS card and narrow receipt crops preserve borders; full white page preserved")
print("PASS originals unchanged; uncrop persists across restart and migration")
print("PASS one PDF retains three independently sized pages")

let padded = try fixture(
  "padded-card", rect: CGRect(x: 580, y: 1100, width: 400, height: 250), padded: true)
let paddedStore = try DraftStore(root: root.appendingPathComponent("padded-store"))
try paddedStore.ingest(padded, autoCrop: true)
let paddedImage = try paddedStore.image(for: paddedStore.visiblePages[0])
expect(
  paddedImage.width >= 400 && paddedImage.width < 415 && paddedImage.height >= 250
    && paddedImage.height < 265, "Two background tones left a full-width strip or clipped the card")
print("PASS device padding and roller background removed independently")

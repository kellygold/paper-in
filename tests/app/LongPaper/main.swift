import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

let fm = FileManager()
let root = fm.temporaryDirectory.appendingPathComponent("PaperIn-LongPaper-\(UUID())")
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
let started = Date()
let width = 2480
let height = 21600
let context = CGContext(
  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setFillColor(CGColor(gray: 0.65, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))
let receipt = CGRect(x: 60, y: 40, width: 930, height: 21520)
context.setFillColor(CGColor(gray: 1, alpha: 1))
context.fill(receipt)
context.setFillColor(CGColor(gray: 0, alpha: 1))
for y in stride(from: 80, through: 21500, by: 120) {
  context.fill(CGRect(x: 100, y: y, width: 750, height: 15))
}
let input = root.appendingPathComponent("receipt.jpg")
let dest = CGImageDestinationCreateWithURL(
  input as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(dest))
let bytes = try Data(contentsOf: input)
let store = try DraftStore(root: root.appendingPathComponent("store"))
try store.beginCapture(expectedSides: 1)
try store.ingest(input, dpi: 300, autoCrop: true, skipBlankBacks: true)
try store.completeCapture(success: true)
let restored = try DraftStore(root: store.root)
let page = restored.visiblePages[0]
precondition(page.width == width && page.height == height)
let image = try restored.image(for: page)
precondition(image.height >= 21520 && image.width >= 930 && image.width < 1100)
let original = try Data(
  contentsOf: restored.folder.appendingPathComponent("sources/" + page.source))
precondition(original == bytes)
let preview = try restored.preview(page)
precondition(preview.pageCount == 1)
let output = try restored.export(to: root.appendingPathComponent("output"))
let pdf = PDFDocument(url: output)!
let bounds = pdf.page(at: 0)!.bounds(for: .mediaBox)
precondition(pdf.pageCount == 1 && bounds.height >= 5164 && bounds.width < 264)
print(
  "PASS maximum-length receipt retains both ends through crop, draft restart, preview and one tall PDF (\(Int(Date().timeIntervalSince(started)))s); original bytes preserved"
)

import AppKit
import CoreGraphics
import CoreText
import PDFKit

// Generated image-only inputs; never open personal scans or use a provider.
let fm = FileManager()
let root = fm.temporaryDirectory.appendingPathComponent("PaperIn-Searchable-\(UUID())")
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }

func fixture(_ name: String, width: Int, height: Int, lines: [(String, Int)]) throws -> URL {
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
  NSColor.white.setFill()
  NSRect(x: 0, y: 0, width: width, height: height).fill()
  for (text, y) in lines {
    (text as NSString).draw(
      at: NSPoint(x: 80, y: y),
      withAttributes: [.font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black])
  }
  NSGraphicsContext.restoreGraphicsState()
  let url = root.appendingPathComponent(name + ".png")
  try bitmap.representation(using: .png, properties: [:])!.write(to: url)
  return url
}

// CoreGraphics sees only persisted PDF operators, unlike a Live Text-enabled view.
func hasTextOperators(_ page: CGPDFPage) -> Bool {
  let table = CGPDFOperatorTableCreate()!
  let markText: CGPDFOperatorCallback = { _, info in
    info!.assumingMemoryBound(to: Bool.self).pointee = true
  }
  for name in ["Tj", "TJ", "'", "\""] {
    CGPDFOperatorTableSetCallback(table, name, markText)
  }
  let stream = CGPDFContentStreamCreateWithPage(page)
  defer { CGPDFContentStreamRelease(stream) }
  var found = false
  withUnsafeMutablePointer(to: &found) { pointer in
    let scanner = CGPDFScannerCreate(stream, table, pointer)
    defer { CGPDFScannerRelease(scanner) }
    precondition(CGPDFScannerScan(scanner))
  }
  return found
}

func render(_ page: CGPDFPage) -> Data {
  let rect = page.getBoxRect(.mediaBox)
  let context = CGContext(
    data: nil, width: Int(rect.width.rounded(.up)), height: Int(rect.height.rounded(.up)),
    bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.setFillColor(CGColor(gray: 1, alpha: 1))
  context.fill(rect)
  context.drawPDFPage(page)
  return Data(bytes: context.data!, count: context.bytesPerRow * context.height)
}

let receipt = try fixture(
  "receipt", width: 1200, height: 2000,
  lines: [
    ("Paper In synthetic receipt", 1800), ("Invoice 82746", 1600), ("Total AUD 139.00", 1400),
  ])
// About 1.5 m at 300 dpi. Verify recognition near both ends and the middle.
let long = try fixture(
  "long", width: 945, height: 18000,
  lines: [
    ("Receipt start 12345", 17600), ("Boundary item 55555", 15145),
    ("Boundary item 66666", 12310), ("Middle item 67890", 9000), ("Total AUD 246.80", 200),
  ])
let blank = try fixture("blank", width: 1200, height: 2000, lines: [])
let store = try DraftStore(root: root.appendingPathComponent("draft"))
for url in [receipt, long, receipt, blank, long] { try store.ingest(url, dpi: 300) }
try store.rotate(store.visiblePages[2].id)
try store.rotate(store.visiblePages[4].id)
// Removal/order and restart must also apply to the saved text layer.
try store.ingest(receipt)
try store.remove(store.visiblePages.last!.id)
let resumed = try DraftStore(root: store.root)
let baseline = PDFDocument()
for page in resumed.visiblePages {
  baseline.insert(try resumed.preview(page).page(at: 0)!, at: baseline.pageCount)
}
let baselineData = baseline.dataRepresentation()!
let sourcePDF = CGPDFDocument(CGDataProvider(data: baselineData as CFData)!)!
precondition(!hasTextOperators(sourcePDF.page(at: 1)!))
let sourceFolder = resumed.folder
let originals = try resumed.visiblePages.map { page in
  (page.source, try Data(contentsOf: sourceFolder.appendingPathComponent("sources/\(page.source)")))
}
let output = try resumed.export(to: root.appendingPathComponent("output"))
let result = PDFDocument(url: output)!
precondition(
  result.documentAttributes?[PDFDocumentAttribute.creatorAttribute] as? String
    == "Paper In (searchable PDF)")
let exported = CGPDFDocument(output as CFURL)!
precondition(result.pageCount == 5 && exported.numberOfPages == 5)
for index in 1...5 {
  let before = sourcePDF.page(at: index)!
  let after = exported.page(at: index)!
  precondition(before.getBoxRect(.mediaBox) == after.getBoxRect(.mediaBox))
  precondition(before.rotationAngle == after.rotationAngle)
  precondition(render(before) == render(after), "OCR changed the visible page \(index)")
  if index != 4 { precondition(hasTextOperators(after), "No persisted text on page \(index)") }
}
let expected = [
  ["82746", "139.00"], ["12345", "55555", "66666", "67890", "246.80"],
  ["82746", "139.00"], [], ["12345", "55555", "66666", "67890", "246.80"],
]
for (index, fragments) in expected.enumerated() {
  let text = result.page(at: index)!.string ?? ""
  for fragment in fragments {
    precondition(
      text.components(separatedBy: fragment).count == 2,
      "Missing or duplicated \(fragment) on page \(index + 1)")
  }
}
precondition(
  (result.page(at: 3)!.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
for (name, data) in originals {
  let retained = try Data(contentsOf: sourceFolder.appendingPathComponent("sources/\(name)"))
  precondition(retained == data)
}
let reopened = try DraftStore(root: store.root)
precondition(reopened.visiblePages.isEmpty)
print(
  "PASS persisted searchable text: receipt, long receipt, rotation, blank page, removed page, restart"
)
print("PASS searchable PDF preserves rendered pixels, page geometry and source bytes")

// A recognized layer must not turn uncertain scan text into confidence=1 for
// filing. Give the helper deliberately wrong embedded text over a known image.
if CommandLine.arguments.count > 1 {
  let bytes = NSMutableData()
  var box = sourcePDF.page(at: 1)!.getBoxRect(.mediaBox)
  let context = CGContext(consumer: CGDataConsumer(data: bytes)!, mediaBox: &box, nil)!
  context.beginPDFPage(nil)
  context.drawPDFPage(sourcePDF.page(at: 1)!)
  context.setTextDrawingMode(.invisible)
  context.textPosition = CGPoint(x: 20, y: 20)
  CTLineDraw(
    CTLineCreateWithAttributedString(
      NSAttributedString(
        string: "Bogus embedded text that should never bypass scan recognition",
        attributes: [.font: NSFont.systemFont(ofSize: 8)])), context)
  context.endPDFPage()
  context.closePDF()
  let marked = PDFDocument(data: bytes as Data)!
  marked.documentAttributes = [PDFDocumentAttribute.creatorAttribute: "Paper In (searchable PDF)"]
  let markedURL = root.appendingPathComponent("incorrect-layer.pdf")
  precondition(marked.write(to: markedURL))
  precondition(PDFDocument(url: markedURL)!.string!.contains("Bogus"))
  let process = Process()
  process.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
  process.arguments = [markedURL.path]
  let pipe = Pipe()
  process.standardOutput = pipe
  try process.run()
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  precondition(process.terminationStatus == 0)
  let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
  let page = (json["pages"] as! [[String: Any]])[0]
  let text = page["text"] as! String
  precondition(text.contains("82746") && !text.contains("Bogus"))
  print("PASS AI filing recognizes the scan instead of trusting its embedded OCR layer")
}

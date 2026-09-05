import AppKit
import PDFKit

let fm = FileManager()
let root = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
let provider = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "codex"
try fm.createDirectory(at: root, withIntermediateDirectories: true)
try Data("Paper In synthetic integration fixture".utf8).write(
  to: root.appendingPathComponent(".synthetic-fixture"))
let output = root.appendingPathComponent("Scans")
try fm.createDirectory(
  at: output.appendingPathComponent("Car/Servicing"), withIntermediateDirectories: true)
try fm.createDirectory(
  at: output.appendingPathComponent("Medical"), withIntermediateDirectories: true)
let image = NSImage(size: NSSize(width: 600, height: 800))
image.lockFocus()
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: 600, height: 800).fill()
let text =
  "SYNTHETIC TEST DOCUMENT\nExample Auto Workshop\nVehicle service invoice DEMO-123\nDate: 14 August 2026\nOil change and vehicle service\nTotal AUD 120.00\nThis is fictional test data."
(text as NSString).draw(
  in: NSRect(x: 45, y: 100, width: 510, height: 620),
  withAttributes: [.font: NSFont.systemFont(ofSize: 23), .foregroundColor: NSColor.black])
image.unlockFocus()
let source = root.appendingPathComponent("fixture.tiff")
try image.tiffRepresentation!.write(to: source)
let store = try DraftStore(root: root)
try store.beginCapture(expectedSides: 1)
try store.ingest(source, dpi: 72)
try store.completeCapture(success: true)
var settings = FilingSettings()
settings.enabled = true
settings.provider = provider
settings.model = ProcessInfo.processInfo.environment["PAPER_IN_TEST_MODEL"] ?? ""
let exported = try store.export(
  to: output.appendingPathComponent("_Inbox"),
  filing: ExportFilingIntent(root: output.path, settings: settings))
print(exported.path)

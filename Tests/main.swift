import AppKit
import PDFKit
import ImageIO
import CryptoKit

let fm = FileManager()
let base = fm.temporaryDirectory.appendingPathComponent("PaperIn-Tests-\(UUID().uuidString)")
try fm.createDirectory(at: base, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: base) }
var passed = 0
func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !value() { throw PaperError("TEST FAILED: \(message)") }
}
func test(_ name: String, _ action: () throws -> Void) throws {
    try action(); passed += 1; print("PASS \(name)")
}
func fixture(_ name: String, frames: Int = 1, orientation: Int = 1) throws -> URL {
    let url = base.appendingPathComponent(name + ".tiff")
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, frames, nil) else { throw PaperError("Fixture destination") }
    for index in 0..<frames {
        let context = CGContext(data: nil, width: 96, height: 160, bitsPerComponent: 8, bytesPerRow: 384, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(index % 2 == 0 ? NSColor.systemRed.cgColor : NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 96, height: 160))
        let properties = [kCGImagePropertyDPIWidth: 72, kCGImagePropertyDPIHeight: 72, kCGImagePropertyOrientation: orientation] as CFDictionary
        CGImageDestinationAddImage(destination, context.makeImage()!, properties)
    }
    guard CGImageDestinationFinalize(destination) else { throw PaperError("Fixture write") }
    return url
}
let single = try fixture("single")
let duplex = try fixture("duplex", frames: 2)

try test("Append across restart, preserve original bytes and two-sided order") {
    let root = base.appendingPathComponent("append")
    var store = try DraftStore(root: root)
    try store.beginCapture(); try store.ingest(single); try store.completeCapture(success: true)
    let first = store.visiblePages[0]
    try expect(try Data(contentsOf: single) == Data(contentsOf: store.folder.appendingPathComponent("sources/\(first.source)")), "Original image bytes changed")
    store = try DraftStore(root: root)
    try store.ingest(duplex)
    try expect(store.visiblePages.count == 3, "Append lost pages")
    try expect(store.visiblePages.map(\.frame) == [0, 0, 1], "Duplex order changed")
    let exported = try store.export(to: base.appendingPathComponent("output-append"))
    let pdf = PDFDocument(url: exported)!
    try expect(pdf.pageCount == 3, "PDF lost a side")
    try expect(abs(pdf.page(at: 0)!.bounds(for: .mediaBox).width - 96) < 1, "PDF physical width is wrong")
    try expect(store.visiblePages.isEmpty, "Save did not start a new draft")
}
try test("Interrupted capture survives restart") {
    let root = base.appendingPathComponent("interrupted")
    let store = try DraftStore(root: root); try store.ingest(single); try store.beginCapture()
    let recovered = try DraftStore(root: root)
    try expect(recovered.draft.interrupted && recovered.visiblePages.count == 1, "Interrupted draft wasn't restored")
}
try test("Recover page received before manifest write failure exactly once") {
    let root = base.appendingPathComponent("failed-manifest")
    let store = try DraftStore(root: root)
    store.beforeWrite = { if $0.lastPathComponent == "manifest.json" { throw PaperError("Simulated disk full") } }
    do { try store.ingest(single); throw PaperError("Failure wasn't surfaced") } catch { try expect(store.visiblePages.isEmpty, "Reported saved before commit") }
    let recovered = try DraftStore(root: root)
    try expect(recovered.visiblePages.count == 1 && recovered.recoveredCount == 1, "Completed page wasn't recovered")
    try expect(try DraftStore(root: root).visiblePages.count == 1, "Recovery duplicated a page")
}
try test("Rotation, reordering and reversible removal survive restart") {
    let root = base.appendingPathComponent("edits")
    var store = try DraftStore(root: root); try store.ingest(duplex)
    let first = store.visiblePages[0].id, second = store.visiblePages[1].id
    try store.rotate(first); try store.move(first, by: 1); try store.remove(second)
    store = try DraftStore(root: root)
    try expect(store.visiblePages.count == 1 && store.visiblePages[0].rotation == 90, "Edits lost")
    try store.restoreLastRemoved()
    try expect(store.visiblePages.map(\.id) == [second, first], "Restore or reorder changed sequence")
    let exported = try store.export(to: base.appendingPathComponent("output-edits"))
    try expect(PDFDocument(url: exported)!.page(at: 1)!.rotation == 90, "Rotation missing from PDF")
}
try test("Export interrupted after publication retries without duplicate PDFs") {
    let root = base.appendingPathComponent("retry-export"), output = base.appendingPathComponent("output-retry")
    let store = try DraftStore(root: root); try store.ingest(single)
    store.beforeWrite = { url in
        if url.lastPathComponent == "manifest.json", store.draft.export != nil { throw PaperError("Simulated interruption after PDF publication") }
    }
    do { _ = try store.export(to: output); throw PaperError("Failure wasn't surfaced") } catch { }
    try expect(store.visiblePages.count == 1, "Export failure cleared draft")
    let recovered = try DraftStore(root: root)
    _ = try recovered.export(to: output)
    try expect(try fm.contentsOfDirectory(atPath: output.path).filter { $0.hasSuffix(".pdf") }.count == 1, "Retry duplicated PDF")
    try expect(recovered.visiblePages.isEmpty, "Retry didn't finalize draft")
}
try test("Output failure retains pages; conflicting file is never overwritten") {
    let root = base.appendingPathComponent("collision"), output = base.appendingPathComponent("output-collision")
    let store = try DraftStore(root: root); try store.ingest(single)
    store.beforeWrite = { url in if url.path.hasPrefix(output.path) { throw PaperError("Output disk full") } }
    do { _ = try store.export(to: output) } catch { }
    try expect(store.visiblePages.count == 1 && store.draft.export != nil, "Output failure lost draft")
    let target = store.draft.export!.destination
    try fm.createDirectory(at: output, withIntermediateDirectories: true)
    let other = Data("Existing unrelated file".utf8); try other.write(to: target)
    store.beforeWrite = nil
    var failed = false
    do { _ = try store.export(to: output) } catch { failed = true }
    try expect(failed, "Collision was not rejected")
    try expect(try Data(contentsOf: target) == other, "Unrelated file overwritten")
}
try test("Organizer may move exported PDF; new document stays independent") {
    let root = base.appendingPathComponent("organizer"), output = base.appendingPathComponent("output-organizer")
    let store = try DraftStore(root: root); try store.ingest(single)
    let first = try store.export(to: output), moved = base.appendingPathComponent("filed.pdf")
    try fm.moveItem(at: first, to: moved)
    try store.ingest(duplex); let second = try store.export(to: output)
    try expect(!fm.fileExists(atPath: first.path), "Old output recreated")
    try expect(PDFDocument(url: moved)!.pageCount == 1 && PDFDocument(url: second)!.pageCount == 2, "Documents contaminated")
}
try test("Unreadable input is rejected without changing previous pages") {
    let store = try DraftStore(root: base.appendingPathComponent("bad-input")); try store.ingest(single)
    let bad = base.appendingPathComponent("bad.image"); try Data("not an image".utf8).write(to: bad)
    var failed = false
    do { try store.ingest(bad) } catch { failed = true }
    try expect(failed && store.visiblePages.count == 1, "Unreadable page accepted")
}
try test("Forty pages produce one complete PDF without an application page limit") {
    let store = try DraftStore(root: base.appendingPathComponent("many"))
    for _ in 0..<20 { try store.ingest(duplex) }
    let url = try store.export(to: base.appendingPathComponent("output-many"))
    try expect(PDFDocument(url: url)!.pageCount == 40, "Large document page count wrong")
}
try test("Scanner image orientation is honored without altering source bytes") {
    let store = try DraftStore(root: base.appendingPathComponent("orientation"))
    let rotated = try fixture("rotated", orientation: 6)
    try store.ingest(rotated)
    let output = try store.export(to: base.appendingPathComponent("output-orientation"))
    let bounds = PDFDocument(url: output)!.page(at: 0)!.bounds(for: .mediaBox)
    try expect(abs(bounds.width - 160) < 1 && abs(bounds.height - 96) < 1, "EXIF orientation was ignored")
}
print("\(passed) persistence and PDF tests passed; no scanner was contacted.")

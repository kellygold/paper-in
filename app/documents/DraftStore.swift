import AppKit
import CryptoKit
import Darwin
import Foundation
import ImageIO
import PDFKit

struct StoredPage: Codable, Identifiable, Equatable {
  var id: String
  var source: String
  var frame: Int
  var width: Int
  var height: Int
  var dpi: Double
  var rotation = 0
  var removed = false
  var crop: PageCrop?
  var cropReviewed: Bool?
  var sheetID: String?
  var side: Int?
  var expectedSides: Int?
  var blankBackSkipped: Bool?
}
struct IngestEnvelope: Codable {
  var id: String
  var received: Date
  var pages: [StoredPage]
}
struct ExportRecord: Codable {
  var destination: URL
  var sha256: String
  var published: Bool
  var filing: ExportFilingIntent?
}
struct CaptureRecord: Codable {
  var id: String
  var expectedSides: Int
  var received: Int
}
struct Draft: Codable {
  var id: String
  var created: Date
  var pages: [StoredPage] = []
  var ingests: [String] = []
  var interrupted = false
  var export: ExportRecord?
  var capture: CaptureRecord?
}

// A single writer owns this store. The UI never reports Saved until commit returns.
final class DraftStore {
  let root: URL
  private(set) var draft: Draft
  var beforeWrite: ((URL) throws -> Void)?  // Fault injection used by persistence tests.
  private let fm = FileManager()
  var folder: URL { root.appendingPathComponent("drafts/\(draft.id)", isDirectory: true) }
  var visiblePages: [StoredPage] { draft.pages.filter { !$0.removed } }
  var recoveredCount = 0

  init(root: URL) throws {
    self.root = root
    try fm.createDirectory(
      at: root.appendingPathComponent("drafts"), withIntermediateDirectories: true)
    let pointer = root.appendingPathComponent("current.json")
    if fm.fileExists(atPath: pointer.path) {
      let id = try JSONDecoder().decode(String.self, from: Data(contentsOf: pointer))
      guard UUID(uuidString: id) != nil else {
        throw PaperError("The draft reference is damaged. Existing files have been preserved.")
      }
      draft = try JSONDecoder().decode(
        Draft.self,
        from: Data(contentsOf: root.appendingPathComponent("drafts/\(id)/manifest.json")))
      guard draft.id == id else {
        throw PaperError("The draft identity does not match its folder.")
      }
    } else {
      draft = Draft(id: UUID().uuidString, created: Date())
      try initializeDraft()
    }
    if draft.export?.published == true { try newDraft() }
    try reconcile()
  }

  private func encoded<T: Encodable>(_ object: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(object)
  }
  private func initializeDraft() throws {
    try fm.createDirectory(
      at: folder.appendingPathComponent("sources"), withIntermediateDirectories: true)
    try fm.createDirectory(
      at: folder.appendingPathComponent("ingests"), withIntermediateDirectories: true)
    try durableWrite(try encoded(draft), to: folder.appendingPathComponent("manifest.json"))
    try durableWrite(try encoded(draft.id), to: root.appendingPathComponent("current.json"))
  }
  private func commit(_ next: Draft) throws {
    try durableWrite(try encoded(next), to: folder.appendingPathComponent("manifest.json"))
    draft = next
  }
  private func newDraft() throws {
    let previous = draft
    draft = Draft(id: UUID().uuidString, created: Date())
    do { try initializeDraft() } catch {
      draft = previous
      throw error
    }
  }
  func durableWrite(_ data: Data, to destination: URL) throws {
    try beforeWrite?(destination)
    let temp = destination.deletingLastPathComponent().appendingPathComponent(
      ".\(UUID().uuidString).partial")
    defer { try? fm.removeItem(at: temp) }
    try data.write(to: temp, options: .withoutOverwriting)
    let fd = open(temp.path, O_RDWR)
    guard fd >= 0 else { throw posix("Open saved data") }
    let syncResult = fsync(fd)
    let savedErrno = errno
    close(fd)
    guard syncResult == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(savedErrno)) }
    guard rename(temp.path, destination.path) == 0 else { throw posix("Commit saved data") }
    let dirFD = open(destination.deletingLastPathComponent().path, O_RDONLY)
    if dirFD >= 0 {
      _ = fsync(dirFD)
      close(dirFD)
    }
  }
  private func posix(_ operation: String) -> Error {
    NSError(
      domain: NSPOSIXErrorDomain, code: Int(errno),
      userInfo: [NSLocalizedDescriptionKey: "\(operation): \(String(cString: strerror(errno)))"])
  }
  private func editable() throws {
    guard draft.export == nil else {
      throw PaperError("A PDF save is pending. Retry Save to finish it before adding pages.")
    }
  }
  func beginCapture(expectedSides: Int = 1) throws {
    try editable()
    try reconcile()
    var next = draft
    next.interrupted = true
    next.capture = CaptureRecord(id: UUID().uuidString, expectedSides: expectedSides, received: 0)
    try commit(next)
  }
  func completeCapture(success: Bool) throws {
    var next = draft
    next.interrupted = !success
    next.capture = nil
    try commit(next)
  }

  @discardableResult func ingest(
    _ input: URL, dpi: Double = 300, autoCrop: Bool = false, skipBlankBacks: Bool = false
  ) throws
    -> Int
  {
    try editable()
    let data = try Data(contentsOf: input)
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetCount(source) > 0
    else {
      throw PaperError("The scanner returned an unreadable image. Earlier pages are saved.")
    }
    let id = UUID().uuidString
    var pages: [StoredPage] = []
    for index in 0..<CGImageSourceGetCount(source) {
      guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else {
        throw PaperError("An incomplete page was received. Earlier pages are saved.")
      }
      let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
      let reportedDPI = (properties?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? dpi
      pages.append(
        StoredPage(
          id: UUID().uuidString, source: "\(id).image", frame: index, width: image.width,
          height: image.height, dpi: reportedDPI > 0 ? reportedDPI : dpi))
    }
    if let capture = draft.capture {
      for index in pages.indices {
        let ordinal = capture.received + index
        pages[index].sheetID = capture.id
        pages[index].side = ordinal
        pages[index].expectedSides = capture.expectedSides
      }
    }
    try durableWrite(data, to: folder.appendingPathComponent("sources/\(id).image"))
    for index in pages.indices {
      pages[index].cropReviewed = true
      let isBack = pages[index].expectedSides == 2 && pages[index].side == 1
      if autoCrop || (skipBlankBacks && isBack) {
        let original = try image(for: pages[index], cropped: false)
        let crop = AutoCrop.detect(original)
        if autoCrop { pages[index].crop = crop }
        if skipBlankBacks && isBack,
          BlankPageDetector.isClearlyBlank(
            crop.map { $0.width * $0.height < 0.9 ? AutoCrop.apply($0, to: original) : original }
              ?? original)
        {
          pages[index].removed = true
          pages[index].blankBackSkipped = true
        }
      }
    }
    let envelope = IngestEnvelope(id: id, received: Date(), pages: pages)
    try durableWrite(try encoded(envelope), to: folder.appendingPathComponent("ingests/\(id).json"))
    var next = draft
    next.pages += pages
    next.ingests.append(id)
    next.capture?.received += pages.count
    try commit(next)
    return pages.count
  }
  private func reconcile() throws {
    guard draft.export == nil else { return }
    let envelopes = try fm.contentsOfDirectory(
      at: folder.appendingPathComponent("ingests"), includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "json" }
    .map { try JSONDecoder().decode(IngestEnvelope.self, from: Data(contentsOf: $0)) }
    .sorted { $0.received < $1.received }
    var next = draft
    for envelope in envelopes where !next.ingests.contains(envelope.id) {
      for page in envelope.pages { _ = try image(for: page) }
      next.pages += envelope.pages
      next.ingests.append(envelope.id)
      recoveredCount += envelope.pages.count
    }
    if recoveredCount > 0 {
      next.interrupted = true
      try commit(next)
    }
    for page in draft.pages {
      guard fm.fileExists(atPath: folder.appendingPathComponent("sources/\(page.source)").path)
      else {
        throw PaperError("A saved page file is missing. The draft has been kept for recovery.")
      }
    }
  }
  func image(for page: StoredPage, cropped: Bool = true) throws -> CGImage {
    let url = folder.appendingPathComponent("sources/\(page.source)")
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, page.frame,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: max(page.width, page.height),
        ] as CFDictionary)
    else { throw PaperError("A saved page could not be opened.") }
    return cropped ? AutoCrop.apply(page.crop, to: image) : image
  }
  func setAutoCrop(_ id: String, enabled: Bool) throws {
    guard let page = draft.pages.first(where: { $0.id == id }) else { return }
    let crop = enabled ? AutoCrop.detect(try image(for: page, cropped: false)) : nil
    try update(id) {
      $0.crop = crop
      $0.cropReviewed = true
    }
  }
  func cropUnreviewedPages() throws {
    guard draft.export == nil else { return }
    try editable()
    var next = draft
    for index in next.pages.indices where next.pages[index].cropReviewed == nil {
      next.pages[index].crop = AutoCrop.detect(try image(for: next.pages[index], cropped: false))
      next.pages[index].cropReviewed = true
    }
    if next.pages != draft.pages { try commit(next) }
  }
  func rotate(_ id: String) throws { try update(id) { $0.rotation = ($0.rotation + 90) % 360 } }
  func remove(_ id: String) throws {
    try update(id) {
      $0.removed = true
      $0.blankBackSkipped = nil
    }
  }
  func restore(_ id: String) throws {
    try update(id) {
      $0.removed = false
      $0.blankBackSkipped = nil
    }
  }
  private func update(_ id: String, change: (inout StoredPage) -> Void) throws {
    try editable()
    var next = draft
    guard let index = next.pages.firstIndex(where: { $0.id == id }) else { return }
    change(&next.pages[index])
    try commit(next)
  }
  func restoreLastRemoved() throws {
    try editable()
    var next = draft
    // A user-removed front must be restored before its automatically skipped back.
    guard
      let index = next.pages.lastIndex(where: { $0.removed && $0.blankBackSkipped != true })
        ?? next.pages.lastIndex(where: { $0.removed })
    else { return }
    next.pages[index].removed = false
    next.pages[index].blankBackSkipped = nil
    try commit(next)
  }
  func move(_ id: String, by offset: Int) throws {
    try editable()
    let visible = visiblePages
    guard let current = visible.firstIndex(where: { $0.id == id }),
      visible.indices.contains(current + offset),
      let from = draft.pages.firstIndex(where: { $0.id == id }),
      let to = draft.pages.firstIndex(where: { $0.id == visible[current + offset].id })
    else { return }
    var next = draft
    next.pages.swapAt(from, to)
    try commit(next)
  }
  func thumbnail(_ page: StoredPage) -> NSImage? {
    let url = folder.appendingPathComponent("sources/\(page.source)")
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, page.frame,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: 140,
        ] as CFDictionary)
    else { return nil }
    return NSImage(cgImage: AutoCrop.apply(page.crop, to: image), size: .zero)
  }
  func preview(_ page: StoredPage) throws -> PDFDocument {
    let doc = PDFDocument()
    doc.insert(try pdfPage(page), at: 0)
    return doc
  }
  private func pdfPage(_ page: StoredPage) throws -> PDFPage {
    let image = try image(for: page)
    let size = NSSize(
      width: Double(image.width) * 72 / page.dpi, height: Double(image.height) * 72 / page.dpi)
    guard let result = PDFPage(image: NSImage(cgImage: image, size: size)) else {
      throw PaperError("Could not render a saved page.")
    }
    result.rotation = page.rotation
    return result
  }
  private func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  // The pending export is recorded before publication, making retries idempotent.
  func export(to destination: URL, filing: ExportFilingIntent? = nil) throws -> URL {
    guard !visiblePages.isEmpty else { throw PaperError("Add a page before saving a PDF.") }
    if draft.export == nil {
      let doc = PDFDocument()
      for (index, page) in visiblePages.enumerated() { doc.insert(try pdfPage(page), at: index) }
      guard let data = doc.dataRepresentation(), let check = PDFDocument(data: data),
        check.pageCount == visiblePages.count
      else { throw PaperError("PDF verification failed. Your pages are still saved.") }
      try durableWrite(data, to: folder.appendingPathComponent("export.pdf"))
      let date = DateFormatter()
      date.dateFormat = "yyyy-MM-dd HH.mm.ss"
      let name = "Scan \(date.string(from: draft.created)) \(draft.id.prefix(8)).pdf"
      var next = draft
      next.export = ExportRecord(
        destination: destination.appendingPathComponent(name), sha256: hash(data), published: false,
        filing: filing)
      try commit(next)
    }
    guard var record = draft.export else { throw PaperError("The pending PDF is unavailable.") }
    let data = try Data(contentsOf: folder.appendingPathComponent("export.pdf"))
    guard hash(data) == record.sha256 else {
      throw PaperError("The pending PDF has changed. Source pages are preserved.")
    }
    if fm.fileExists(atPath: record.destination.path) {
      guard hash(try Data(contentsOf: record.destination)) == record.sha256 else {
        throw PaperError(
          "A different file already exists at the output name. Nothing was overwritten.")
      }
    } else {
      let parent = record.destination.deletingLastPathComponent()
      try fm.createDirectory(at: parent, withIntermediateDirectories: true)
      let staged = parent.appendingPathComponent(".\(UUID().uuidString).partial")
      defer { try? fm.removeItem(at: staged) }
      try durableWrite(data, to: staged)
      // Hard-link publication is atomic and fails if the final name already exists.
      guard link(staged.path, record.destination.path) == 0 else { throw posix("Publish PDF") }
      let fd = open(parent.path, O_RDONLY)
      if fd >= 0 {
        _ = fsync(fd)
        close(fd)
      }
    }
    record.published = true
    var next = draft
    next.export = record
    next.interrupted = false
    try commit(next)
    try newDraft()
    return record.destination
  }
}

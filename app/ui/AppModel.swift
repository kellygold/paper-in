import AppKit
import Foundation
import PDFKit
import SwiftUI

final class AppModel: ObservableObject {
  @Published var pages: [StoredPage] = []
  @Published var selected: String?
  @Published var preview: PDFDocument?
  @Published var sheetPreviews: [String: PDFDocument] = [:]
  @Published var sheets: [SheetGroup] = []
  @Published var pairedPreview = true
  @Published var connection: ScannerConnection
  var selectedSheet: SheetGroup? { sheets.first { $0.pages.contains { $0.id == selected } } }
  var filing: FilingController!
  @Published var notice: String?
  @Published var failure: String?
  @Published var destination: URL
  @Published var duplex = UserDefaults().object(forKey: "bothSides") as? Bool ?? true
  @Published var autoCrop = UserDefaults().object(forKey: "autoCrop") as? Bool ?? true
  @Published var skipBlankBacks = UserDefaults().object(forKey: "skipBlankBacks") as? Bool ?? false
  @Published var exporting = false
  @Published var exportPending = false
  @Published var hasRemovedPages = false
  @Published var lastExport: URL?
  let scanner: ScannerSession
  private(set) var store: DraftStore?
  let demo: Bool
  let root: URL
  var canEdit: Bool { store != nil && !scanner.busy && !exporting && !exportPending }

  init() {
    let savedConnection =
      ScannerConnection(rawValue: UserDefaults().string(forKey: "scannerConnection") ?? "usb")
      ?? .usb
    connection = savedConnection
    demo = CommandLine.arguments.contains("--demo")
    let fm = FileManager()
    if demo {
      root = fm.temporaryDirectory.appendingPathComponent(
        "PaperIn-Demo-\(ProcessInfo.processInfo.processIdentifier)")
    } else {
      root = fm.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support/Paper In")
    }
    let saved = UserDefaults().string(forKey: "outputFolder")
    destination =
      demo
      ? root.appendingPathComponent("Output")
      : saved.map { URL(fileURLWithPath: $0) }
        ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Scanned Documents")
    filing = FilingController(root: root, demo: demo)
    scanner = ScannerCatalog.makeSession(
      staging: root.appendingPathComponent("transfers"), connection: savedConnection)
    do {
      store = try DraftStore(root: root)
      if autoCrop && !demo { try store?.cropUnreviewedPages() }
      if store?.draft.interrupted == true {
        notice =
          "The last scan was interrupted. Your saved pages are here; check the last sheet before continuing."
      }
      if demo {
        try store?.beginCapture(expectedSides: 2)
        try makeSample()
        try makeSample()
        try store?.completeCapture(success: true)
        notice = "Preview mode — no scanner connection"
      }
      refresh()
    } catch {
      failure =
        "Couldn’t open the draft: \(error.localizedDescription). Existing files have been preserved."
    }
    scanner.onBegin = { [weak self] options in
      guard let self, let store = self.store, !self.exporting else {
        throw PaperError("The draft isn’t ready for a new page.")
      }
      try store.beginCapture(expectedSides: options.duplex ? 2 : 1)
      self.notice = nil
      self.failure = nil
    }
    scanner.onPage = { [weak self] url, dpi in
      guard let self, let store = self.store else {
        throw PaperError("Draft storage isn’t available.")
      }
      try store.ingest(
        url, dpi: dpi, autoCrop: self.autoCrop, skipBlankBacks: self.skipBlankBacks)
      self.refresh(selectLast: true)
    }
    scanner.onEnd = { [weak self] success, error in
      guard let self else { return }
      do { try self.store?.completeCapture(success: success) } catch {
        self.failure = error.localizedDescription
      }
      if let error { self.notice = error }
      self.refresh()
    }
  }
  func refresh(selectLast: Bool = false) {
    pages = store?.visiblePages ?? []
    sheets = SheetGroup.make(store?.draft.pages ?? [])
    exportPending = store?.draft.export != nil
    hasRemovedPages = store?.draft.pages.contains(where: { $0.removed }) ?? false
    if selectLast { selected = pages.last?.id }
    if !pages.contains(where: { $0.id == selected }) { selected = pages.first?.id }
    select(selected)
  }
  func select(_ id: String?) {
    selected = id
    guard let page = pages.first(where: { $0.id == id }) else {
      preview = nil
      return
    }
    do {
      preview = try store?.preview(page)
      sheetPreviews = [:]
      for sibling in selectedSheet?.visible ?? [] {
        sheetPreviews[sibling.id] = try store?.preview(sibling)
      }
    } catch { failure = error.localizedDescription }
  }
  var selectedPageIndex: Int? { pages.firstIndex { $0.id == selected } }
  func navigatePage(by offset: Int) {
    guard let index = selectedPageIndex, pages.indices.contains(index + offset) else { return }
    select(pages[index + offset].id)
  }
  func edit(_ action: (DraftStore) throws -> Void) {
    guard canEdit, let store else { return }
    let previousIndex = selectedPageIndex
    let previousID = selected
    let previousSheetID = selectedSheet?.id
    do {
      try action(store)
      refresh()
      if let previousIndex, !pages.isEmpty, !pages.contains(where: { $0.id == previousID }) {
        let sibling =
          pairedPreview
          ? sheets.first(where: { $0.id == previousSheetID })?.visible.first?.id : nil
        select(sibling ?? pages[min(previousIndex, pages.count - 1)].id)
      }
    } catch { failure = error.localizedDescription }
  }
  func changeConnection(_ next: ScannerConnection) {
    guard !scanner.busy else { return }
    scanner.replaceBackend(
      ScannerCatalog.makeBackend(
        staging: root.appendingPathComponent("transfers"), connection: next))
    if !demo { UserDefaults().set(next.rawValue, forKey: "scannerConnection") }
  }
  func scan() {
    guard canEdit else { return }
    if demo {
      do {
        try store?.beginCapture(expectedSides: duplex ? 2 : 1)
        try makeSample()
        if duplex { try makeSample() }
        try store?.completeCapture(success: true)
        refresh(selectLast: true)
      } catch { failure = error.localizedDescription }
      return
    }
    scanner.duplex = duplex
    scanner.scan()
  }
  func save() {
    guard !scanner.busy, !exporting, !pages.isEmpty, let store else { return }
    exporting = true
    failure = nil
    DispatchQueue.main.async { [self] in
      defer {
        exporting = false
        refresh()
      }
      do {
        scanner.diagnostics.event("pdf_save_requested", ["pages": pages.count])
        let root = destination.resolvingSymlinksInPath().standardizedFileURL
        let intent =
          filing.settings.enabled && !demo
          ? ExportFilingIntent(root: root.path, settings: filing.settings) : nil
        let output = intent == nil ? destination : root.appendingPathComponent("_Inbox")
        lastExport = try store.export(to: output, filing: intent)
        filing.run()
        scanner.diagnostics.event("pdf_saved")
        notice = "PDF saved. Ready for a new document."
      } catch {
        scanner.diagnostics.event("pdf_save_failed", error: error)
        failure =
          "Couldn’t finish saving: \(error.localizedDescription) Your draft is preserved; retry Save PDF."
      }
    }
  }
  func chooseFolder() {
    guard !exporting, !exportPending else { return }
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.prompt = "Use this folder"
    panel.directoryURL = destination
    if panel.runModal() == .OK, let folder = panel.url {
      destination = folder
      if !demo { UserDefaults().set(folder.path, forKey: "outputFolder") }
    }
  }
  private func makeSample() throws {
    let size = NSSize(width: 620, height: 877)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 9
    let body =
      "A place for every page.\n\nInsert a sheet. Press Start.\nKeep adding pages to this document.\n\nWhen you’re ready, Save PDF sends the\nwhole document to your chosen folder.\n\nEach completed page stays saved,\neven if the scanner disconnects."
    ("Paper In" as NSString).draw(
      at: NSPoint(x: 62, y: 749),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 38, weight: .semibold),
        .foregroundColor: NSColor(calibratedRed: 0.10, green: 0.33, blue: 0.30, alpha: 1),
      ])
    (body as NSString).draw(
      in: NSRect(x: 62, y: 250, width: 495, height: 440),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.darkGray,
        .paragraphStyle: paragraph,
      ])
    ("SAMPLE PAGE · \((store?.visiblePages.count ?? 0) + 1)" as NSString).draw(
      at: NSPoint(x: 62, y: 75),
      withAttributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor.gray,
      ])
    image.unlockFocus()
    guard let data = image.tiffRepresentation else {
      throw PaperError("Couldn’t create preview page.")
    }
    let url = root.appendingPathComponent("sample.tiff")
    try data.write(to: url)
    try store?.ingest(url, dpi: 72)
  }
}

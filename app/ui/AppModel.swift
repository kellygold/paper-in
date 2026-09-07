import AppKit
import Foundation
import PDFKit
import SwiftUI

final class AppModel: ObservableObject {
  @Published var pages: [StoredPage] = []
  @Published var selected: String?
  @Published var previewFolder: URL?
  @Published var preview: NSImage?
  @Published var sheetPreviews: [String: NSImage] = [:]
  @Published var sheets: [SheetGroup] = []
  @Published var pairedPreview = true
  @Published var connection: ScannerConnection
  var selectedSheet: SheetGroup? { sheets.first { $0.pages.contains { $0.id == selected } } }
  var filing: FilingController!
  @Published var notice: String?
  @Published var failure: String?
  @Published var destination: URL
  @Published var duplex = UserDefaults().object(forKey: "bothSides") as? Bool ?? true
  private var preferredDuplex = UserDefaults().object(forKey: "bothSides") as? Bool ?? true
  @Published var paperMode = AppModel.savedPaperMode(in: UserDefaults())
  @Published var autoCrop = UserDefaults().object(forKey: "autoCrop") as? Bool ?? true
  @Published var skipBlanks = AppModel.savedSkipBlanks(in: UserDefaults())
  static func savedSkipBlanks(in defaults: UserDefaults) -> Bool {
    defaults.object(forKey: "skipBlanks") as? Bool
      ?? defaults.object(forKey: "skipBlankBacks") as? Bool ?? false
  }
  static func savedPaperMode(in defaults: UserDefaults) -> ScanPaperMode {
    ScanPaperMode(rawValue: defaults.string(forKey: "paperMode") ?? "standard") ?? .standard
  }
  @Published var exporting = false
  @Published var exportPending = false
  @Published var hasRemovedPages = false
  @Published var lastExport: URL?
  let scanner: ScannerSession
  private(set) var store: DraftStore?
  let demo: Bool
  let root: URL
  @Published var skippedPageCount = 0
  var canScanBothSides: Bool {
    demo ? paperMode != .longPaper : scanner.supportsDuplex(for: paperMode)
  }
  var availablePaperModes: [ScanPaperMode] {
    let modes = demo ? ScanPaperMode.allCases : scanner.paperModes
    return modes.contains(paperMode) ? modes : [paperMode] + modes
  }
  func chooseSides(_ both: Bool) {
    guard !both || canScanBothSides else { return }
    preferredDuplex = both
    duplex = both
    if !demo { UserDefaults().set(both, forKey: "bothSides") }
  }
  func choosePaperMode(_ mode: ScanPaperMode) {
    paperMode = mode
    if !demo { UserDefaults().set(mode.rawValue, forKey: "paperMode") }
    if demo || scanner.connected { duplex = preferredDuplex && canScanBothSides }
  }
  func reconcilePaperModes() {
    guard !demo, scanner.connected else { return }
    if !scanner.paperModes.contains(paperMode) { choosePaperMode(.standard) }
    duplex = preferredDuplex && canScanBothSides
  }
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
    restoreDraft(autoCrop: autoCrop && !demo)
    if demo {
      do {
        try store?.beginCapture(expectedSides: 2)
        try makeSample()
        try makeSample()
        try store?.completeCapture(success: true)
        notice = "Preview mode — no scanner connection"
      } catch { failure = error.localizedDescription }
      refresh()
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
        url, dpi: dpi, autoCrop: self.autoCrop, skipBlanks: self.skipBlanks)
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
  func restoreDraft(autoCrop: Bool) {
    defer { refresh() }
    do { store = try DraftStore(root: root) } catch {
      failure =
        "Couldn’t open the draft: \(error.localizedDescription). Existing files have been preserved."
      return
    }
    if store?.draft.interrupted == true {
      notice =
        "The last scan was interrupted. Your saved pages are here; check the last sheet before continuing."
    }
    do {
      if autoCrop { try store?.cropUnreviewedPages() }
    } catch {
      failure =
        "Your draft is restored, but some pages could not be cropped: \(error.localizedDescription)"
    }
  }
  func refresh(selectLast: Bool = false, preferredSelection: String? = nil) {
    guard !exporting else { return }
    previewFolder = store?.folder
    skippedPageCount =
      store?.draft.pages.filter { $0.removed && $0.blankSkipped == true }.count ?? 0
    pages = store?.visiblePages ?? []
    sheets = SheetGroup.make(store?.draft.pages ?? [])
    exportPending = store?.draft.export != nil
    hasRemovedPages = store?.draft.pages.contains(where: { $0.removed }) ?? false
    if let preferredSelection { selected = preferredSelection }
    if selectLast { selected = pages.last?.id }
    if !pages.contains(where: { $0.id == selected }) { selected = pages.first?.id }
    select(selected)
  }
  private var previewTask: Task<Void, Never>?
  @Published var previewLoading = false
  func select(_ id: String?) {
    guard !exporting else { return }
    previewTask?.cancel()
    selected = id
    sheetPreviews = [:]
    preview = nil
    guard let page = pages.first(where: { $0.id == id }), let folder = store?.folder else {
      previewLoading = false
      return
    }
    let visible = selectedSheet?.visible ?? [page]
    previewLoading = true
    previewTask = Task { @MainActor [weak self] in
      do {
        var images: [String: NSImage] = [:]
        var issue: String?
        for sibling in visible {
          do {
            let bitmap = try await PreviewRenderer.shared.image(
              folder: folder, page: sibling, pixels: 2400)
            images[sibling.id] = NSImage(cgImage: bitmap.image, size: .zero)
          } catch is CancellationError { throw CancellationError() } catch {
            issue = error.localizedDescription
          }
        }
        try Task.checkCancellation()
        guard let self, !self.exporting, self.selected == id, self.store?.folder == folder else {
          return
        }
        self.sheetPreviews = images
        self.preview = images[page.id]
        self.previewLoading = false
        if let issue { self.failure = issue }
      } catch is CancellationError {
        // A newer selection owns the preview now.
      } catch {
        guard let self, !Task.isCancelled else { return }
        self.previewLoading = false
        self.failure = error.localizedDescription
      }
    }
  }

  var selectedPageIndex: Int? { pages.firstIndex { $0.id == selected } }
  func navigatePage(by offset: Int) {
    guard let index = selectedPageIndex, pages.indices.contains(index + offset) else { return }
    select(pages[index + offset].id)
  }
  func moveSelectedPage(by offset: Int) {
    guard canEdit, let store, let id = selected else { return }
    do {
      try store.move(id, by: offset)
      pairedPreview = false
      refresh()
      notice = "Page moved. Single page view shows the PDF order."
    } catch { failure = error.localizedDescription }
  }
  func edit(_ action: (DraftStore) throws -> Void) {
    guard canEdit, let store else { return }
    let previousIndex = selectedPageIndex
    let previousID = selected
    let previousSheetID = selectedSheet?.id
    do {
      try action(store)
      let remaining = store.visiblePages
      var nextSelection = previousID
      if let previousIndex, !remaining.isEmpty, !remaining.contains(where: { $0.id == previousID })
      {
        let sibling =
          pairedPreview
          ? SheetGroup.make(store.draft.pages).first(where: { $0.id == previousSheetID })?.visible
            .first?.id : nil
        nextSelection = sibling ?? remaining[min(previousIndex, remaining.count - 1)].id
      }
      refresh(preferredSelection: nextSelection)
    } catch { failure = error.localizedDescription }
  }
  func startOver() {
    guard canEdit, let store else { return }
    do {
      try store.discardDraft()
      lastExport = nil
      failure = nil
      notice = "Ready for a new document."
      refresh()
    } catch { failure = error.localizedDescription }
  }
  func changeConnection(_ next: ScannerConnection) {
    guard !scanner.busy, !exporting else { return }
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
    scanner.paperMode = paperMode
    scanner.scan()
  }
  func save() {
    guard !scanner.busy, !exporting, !pages.isEmpty, let store else { return }
    exporting = true
    failure = nil
    previewTask?.cancel()
    scanner.diagnostics.event("pdf_save_requested", ["pages": pages.count])
    let destination = self.destination
    let settings = filing.settings
    let useFiling = settings.enabled && !demo
    DispatchQueue.global(qos: .userInitiated).async { [self] in
      let result: Result<URL, Error> = Result {
        let root = destination.resolvingSymlinksInPath().standardizedFileURL
        let intent = useFiling ? ExportFilingIntent(root: root.path, settings: settings) : nil
        return try store.export(
          to: intent == nil ? destination : root.appendingPathComponent("_Inbox"), filing: intent)
      }
      DispatchQueue.main.async {
        self.exporting = false
        switch result {
        case .success(let output):
          self.lastExport = output
          self.filing.run()
          self.scanner.diagnostics.event("pdf_saved")
          self.notice = "PDF saved. Ready for a new document."
        case .failure(let error):
          self.scanner.diagnostics.event("pdf_save_failed", error: error)
          self.failure =
            "Couldn’t finish saving: \(error.localizedDescription) Your draft is preserved; retry Save PDF."
        }
        self.refresh()
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

import Foundation
import SwiftUI
import PDFKit
import AppKit

final class AppModel: ObservableObject {
    @Published var pages: [StoredPage] = []
    @Published var selected: String?
    @Published var preview: PDFDocument?
    @Published var notice: String?
    @Published var failure: String?
    @Published var destination: URL
    @Published var duplex = UserDefaults().object(forKey: "bothSides") as? Bool ?? true
    @Published var autoCrop = UserDefaults().object(forKey: "autoCrop") as? Bool ?? true
    @Published var exporting = false
    @Published var exportPending = false
    @Published var hasRemovedPages = false
    @Published var lastExport: URL?
    let scanner: USBScannerController
    private(set) var store: DraftStore?
    let demo: Bool
    let root: URL
    var canEdit: Bool { store != nil && !scanner.busy && !exporting && !exportPending }

    init() {
        demo = CommandLine.arguments.contains("--demo")
        let fm = FileManager()
        if demo { root = fm.temporaryDirectory.appendingPathComponent("PaperIn-Demo-\(ProcessInfo.processInfo.processIdentifier)") }
        else { root = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Paper In") }
        let saved = UserDefaults().string(forKey: "outputFolder")
        destination = demo ? root.appendingPathComponent("Output") : saved.map { URL(fileURLWithPath: $0) } ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Scanned Documents")
        scanner = USBScannerController(staging: root.appendingPathComponent("transfers"))
        do {
            store = try DraftStore(root: root)
            if autoCrop && !demo { try store?.cropUnreviewedPages() }
            if store?.draft.interrupted == true { notice = "The last scan was interrupted. Your saved pages are here; check the last sheet before continuing." }
            if demo { try makeSample(); notice = "Preview mode — no scanner connection" }
            refresh()
        } catch { failure = "Couldn’t open the draft: \(error.localizedDescription). Existing files have been preserved." }
        scanner.onBegin = { [weak self] in
            guard let self, let store = self.store, !self.exporting else { throw PaperError("The draft isn’t ready for a new page.") }
            try store.beginCapture(); self.notice = nil; self.failure = nil
        }
        scanner.onPage = { [weak self] url, dpi in
            guard let self, let store = self.store else { throw PaperError("Draft storage isn’t available.") }
            try store.ingest(url, dpi: dpi, autoCrop: self.autoCrop); self.refresh(selectLast: true)
        }
        scanner.onEnd = { [weak self] success, error in
            guard let self else { return }
            do { try self.store?.completeCapture(success: success) } catch { self.failure = error.localizedDescription }
            if let error { self.notice = error }
            self.refresh()
        }
    }
    func refresh(selectLast: Bool = false) {
        pages = store?.visiblePages ?? []
        exportPending = store?.draft.export != nil
        hasRemovedPages = store?.draft.pages.contains(where: { $0.removed }) ?? false
        if selectLast { selected = pages.last?.id }
        if !pages.contains(where: { $0.id == selected }) { selected = pages.first?.id }
        select(selected)
    }
    func select(_ id: String?) {
        selected = id
        guard let page = pages.first(where: { $0.id == id }) else { preview = nil; return }
        do { preview = try store?.preview(page) } catch { failure = error.localizedDescription }
    }
    func edit(_ action: (DraftStore) throws -> Void) {
        guard canEdit, let store else { return }
        do { try action(store); refresh() } catch { failure = error.localizedDescription }
    }
    func scan() {
        guard canEdit else { return }
        if demo { do { try makeSample(); refresh(selectLast: true) } catch { failure = error.localizedDescription }; return }
        scanner.duplex = duplex; scanner.scan()
    }
    func save() {
        guard !scanner.busy, !exporting, !pages.isEmpty, let store else { return }
        exporting = true; failure = nil
        DispatchQueue.main.async { [self] in
            defer { exporting = false; refresh() }
            do {
                scanner.diagnostics.event("pdf_save_requested", ["pages": pages.count])
                lastExport = try store.export(to: destination)
                scanner.diagnostics.event("pdf_saved")
                notice = "PDF saved. Ready for a new document."
            } catch { scanner.diagnostics.event("pdf_save_failed", error: error); failure = "Couldn’t finish saving: \(error.localizedDescription) Your draft is preserved; retry Save PDF." }
        }
    }
    func chooseFolder() {
        guard !exporting, !exportPending else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = true; panel.prompt = "Use this folder"; panel.directoryURL = destination
        if panel.runModal() == .OK, let folder = panel.url {
            destination = folder
            if !demo { UserDefaults().set(folder.path, forKey: "outputFolder") }
        }
    }
    private func makeSample() throws {
        let size = NSSize(width: 620, height: 877)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 9
        let body = "A place for every page.\n\nInsert a sheet. Press Start.\nKeep adding pages to this document.\n\nWhen you’re ready, Save PDF sends the\nwhole document to your chosen folder.\n\nEach completed page stays saved,\neven if the scanner disconnects."
        ("Paper In" as NSString).draw(at: NSPoint(x: 62, y: 749), withAttributes: [.font: NSFont.systemFont(ofSize: 38, weight: .semibold), .foregroundColor: NSColor(calibratedRed: 0.10, green: 0.33, blue: 0.30, alpha: 1)])
        (body as NSString).draw(in: NSRect(x: 62, y: 250, width: 495, height: 440), withAttributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.darkGray, .paragraphStyle: paragraph])
        ("SAMPLE PAGE · \((store?.visiblePages.count ?? 0) + 1)" as NSString).draw(at: NSPoint(x: 62, y: 75), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.gray])
        image.unlockFocus()
        guard let data = image.tiffRepresentation else { throw PaperError("Couldn’t create preview page.") }
        let url = root.appendingPathComponent("sample.tiff"); try data.write(to: url)
        try store?.ingest(url, dpi: 72)
    }
}

struct PageThumbnail: View {
    let store: DraftStore?
    let page: StoredPage
    @State private var thumbnail: NSImage?
    var body: some View {
        Group {
            if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit().rotationEffect(.degrees(Double(page.rotation))) }
            else { Image(systemName: "doc.text").foregroundStyle(.secondary) }
        }.frame(width: 33, height: 44)
         .onAppear { thumbnail = store?.thumbnail(page) }
    }
}

struct PagePreview: View {
    let document: PDFDocument?
    var body: some View {
        GeometryReader { geometry in
            if let page = document?.page(at: 0) {
                let image = page.thumbnail(of: NSSize(width: 1200, height: 1700), for: .mediaBox)
                Image(nsImage: image).resizable().scaledToFit()
                    .padding(22).frame(width: geometry.size.width, height: geometry.size.height)
            }
        }.background(Color(white: 0.925))
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var scanner: USBScannerController
    private let green = Color(red: 0.12, green: 0.36, blue: 0.31)
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Image(systemName: "doc.viewfinder").font(.system(size: 28, weight: .medium)).foregroundStyle(green)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Paper In").font(.system(size: 23, weight: .semibold))
                    Text("One document, as many pages as you need.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(scanner.connected ? green : Color.secondary.opacity(0.5)).frame(width: 7, height: 7)
                Text(model.demo ? "Preview" : scanner.scannerName).font(.system(size: 12))
                if !model.demo {
                    Button(scanner.listening ? "Pause scanner" : "Connect") {
                        if scanner.listening { scanner.pause() } else { scanner.connect() }
                    }.disabled(scanner.busy || model.store == nil)
                    if scanner.listening && !scanner.connected { Button("Retry") { scanner.retry() }.disabled(scanner.busy) }
                }
            }.padding(24)
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("YOUR DOCUMENT").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(model.pages.count)").monospacedDigit().font(.system(size: 12, weight: .medium))
                    }
                    if model.pages.isEmpty {
                        Text("Your pages will appear here.").font(.callout).foregroundStyle(.secondary).padding(.top, 10)
                    }
                    ScrollView {
                        LazyVStack(spacing: 9) {
                            ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                                Button { model.select(page.id) } label: {
                                    HStack(spacing: 10) {
                                        PageThumbnail(store: model.store, page: page)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("Page \(index + 1)").font(.system(size: 13, weight: .medium))
                                            Text("Saved to draft").font(.system(size: 10)).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(green).font(.system(size: 11))
                                    }.padding(12).background(model.selected == page.id ? green.opacity(0.09) : Color.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.selected == page.id ? green.opacity(0.4) : Color.black.opacity(0.06)))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    if model.hasRemovedPages { Button("Restore removed page") { model.edit { try $0.restoreLastRemoved() } }.font(.caption).disabled(!model.canEdit) }
                    Text("Completed pages stay here until you save your PDF.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(20).frame(width: 225)
                Divider()
                VStack(spacing: 0) {
                    if model.pages.isEmpty {
                        VStack(spacing: 15) {
                            Image(systemName: "scanner").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(green)
                            Text("Start with a sheet of paper").font(.system(size: 23, weight: .medium))
                            Text("Scan each sheet, then save them together as one PDF.").foregroundStyle(.secondary)
                            if let last = model.lastExport { Button("Show saved PDF") { NSWorkspace.shared.activateFileViewerSelecting([last]) } }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white)
                    } else {
                        PagePreview(document: model.preview)
                        HStack(spacing: 16) {
                            Text("Page \((model.pages.firstIndex { $0.id == model.selected } ?? 0) + 1) of \(model.pages.count)").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { if let id = model.selected { model.edit { try $0.move(id, by: -1) } } } label: { Label("Earlier", systemImage: "arrow.up") }
                            Button { if let id = model.selected { model.edit { try $0.move(id, by: 1) } } } label: { Label("Later", systemImage: "arrow.down") }
                            Button {
                                if let id = model.selected, let page = model.pages.first(where: { $0.id == id }) { model.edit { try $0.setAutoCrop(id, enabled: page.crop == nil) } }
                            } label: { Label(model.pages.first(where: { $0.id == model.selected })?.crop == nil ? "Auto crop" : "Full scan", systemImage: "crop") }
                            Button { if let id = model.selected { model.edit { try $0.rotate(id) } } } label: { Label("Rotate", systemImage: "rotate.right") }
                            Button { if let id = model.selected { model.edit { try $0.remove(id) } } } label: { Label("Remove", systemImage: "minus.circle") }
                        }.buttonStyle(.borderless).disabled(!model.canEdit).padding(15).background(Color.white)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                if let failure = model.failure {
                    Label(failure, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(Color(red: 0.65, green: 0.20, blue: 0.12)).textSelection(.enabled)
                }
                if let notice = model.notice { Text(notice).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.demo ? "Preview mode — scanner is untouched" : scanner.message).font(.system(size: 13, weight: .medium)).textSelection(.enabled)
                        HStack(spacing: 6) {
                            Text("Up to A4 · 300 dpi · Colour").font(.caption).foregroundStyle(.secondary)
                            Toggle("Both sides", isOn: $model.duplex).toggleStyle(.checkbox).font(.caption)
                                .disabled(!model.canEdit || (!model.demo && !scanner.supportsDuplex))
                                .onChange(of: model.duplex) { _, value in scanner.duplex = value; if !model.demo { UserDefaults().set(value, forKey: "bothSides") } }
                            Toggle("Auto crop", isOn: $model.autoCrop).toggleStyle(.checkbox).font(.caption).disabled(!model.canEdit)
                                .onChange(of: model.autoCrop) { _, value in if !model.demo { UserDefaults().set(value, forKey: "autoCrop") } }
                        }
                        if !model.demo && !scanner.buttonObserved { Text("Use Scan or Space to add a sheet.").font(.system(size: 10)).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 16)
                    if scanner.busy { Button("Stop") { scanner.pause() } }
                    Button { model.scan() } label: { Label(model.pages.isEmpty ? "Scan" : "Scan next page", systemImage: "plus").padding(.horizontal, 8).padding(.vertical, 7) }
                        .keyboardShortcut(.space, modifiers: []).disabled(!model.canEdit || (!model.demo && !scanner.connected))
                    Button { model.save() } label: { Text(model.exporting ? "Saving…" : "Save PDF").fontWeight(.semibold).padding(.horizontal, 16).padding(.vertical, 7) }
                        .buttonStyle(.borderedProminent).tint(green).keyboardShortcut("s", modifiers: .command)
                        .disabled(scanner.busy || model.exporting || model.pages.isEmpty || model.store == nil)
                }
                HStack(spacing: 5) {
                    Image(systemName: "folder"); Text("Save to:")
                    Text(model.destination.path.replacingOccurrences(of: FileManager().homeDirectoryForCurrentUser.path, with: "~")).lineLimit(1).truncationMode(.middle)
                    Button("Change…") { model.chooseFolder() }.buttonStyle(.link).disabled(!model.canEdit)
                    Spacer()
                    if model.pages.count > 0 { Text("\(model.pages.count) \(model.pages.count == 1 ? "page" : "pages") saved in draft").foregroundStyle(green) }
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(20)
        }
        .frame(minWidth: 900, minHeight: 660)
        .background(Color(red: 0.98, green: 0.975, blue: 0.96))
        .onAppear { renderIfRequested() }
    }
    private func renderIfRequested() {
        guard let index = CommandLine.arguments.firstIndex(of: "--screenshot"), CommandLine.arguments.indices.contains(index + 1) else { return }
        let output = CommandLine.arguments[index + 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard let view = NSApplication.shared.windows.first(where: { $0.contentView != nil && $0.frame.width > 500 })?.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
            NSApplication.shared.terminate(nil)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var model: AppModel!
    var window: NSWindow!
    var statusItem: NSStatusItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 800), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.title = "Paper In"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView(model: model, scanner: model.scanner).environment(\.colorScheme, .light))
        window.minSize = NSSize(width: 920, height: 740)
        window.center(); window.makeKeyAndOrderFront(nil)
        let appMenu = NSMenu()
        let rootItem = NSMenuItem(); appMenu.addItem(rootItem)
        let actions = NSMenu(); rootItem.submenu = actions
        actions.addItem(withTitle: "About Paper In", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        actions.addItem(.separator())
        actions.addItem(withTitle: "Quit Paper In", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = appMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "scanner", accessibilityDescription: "Paper In")
        let menu = NSMenu()
        for (title, action) in [("Show Paper In", #selector(show)), ("Scan next page", #selector(scan)), ("Save PDF", #selector(save)), ("Show connection log", #selector(showLog))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator()); menu.addItem(withTitle: "Quit Paper In", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        model.scanner.diagnostics.event("window_opened")
        if !model.demo && CommandLine.arguments.contains("--connect") { model.scanner.connect() }
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func scan() { model.scan() }
    @objc func save() { model.save() }
    @objc func showLog() { NSWorkspace.shared.activateFileViewerSelecting([model.scanner.diagnostics.url]) }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(scan) { return model.canEdit && (model.demo || model.scanner.connected) }
        if item.action == #selector(save) { return !model.scanner.busy && !model.exporting && !model.pages.isEmpty }
        return true
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    func applicationWillTerminate(_ notification: Notification) { model?.scanner.pause() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main enum PaperInApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

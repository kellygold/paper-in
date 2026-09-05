import AppKit
import PDFKit
import SwiftUI

precondition(CommandLine.arguments.contains("--demo"))
let model = AppModel()
model.chooseSides(true)
precondition(
  model.demo && model.pages.count == 2 && model.sheets.count == 1
    && model.selectedSheet?.paired == true)
let back = model.pages[1].id
model.pairedPreview = false
model.select(model.pages[0].id)
model.navigatePage(by: 1)
precondition(model.selected == back)
model.navigatePage(by: 1)
precondition(model.selected == back)
model.navigatePage(by: -1)
precondition(model.selected == model.pages[0].id)
model.pairedPreview = true
model.select(back)
precondition(model.selected == back && model.sheetPreviews.count == 2)
model.edit {
  try $0.rotate(back)
  try $0.remove(back)
}
precondition(
  model.pages.count == 1 && model.sheets.count == 1
    && model.selectedSheet?.page(side: 1)?.removed == true)
model.edit { try $0.restoreLastRemoved() }
model.scan()
precondition(model.pages.count == 4 && model.sheets.count == 2)
let newestBack = model.pages[3].id
let newestFront = model.pages[2].id
model.select(newestBack)
model.edit { try $0.remove(newestBack) }
precondition(model.selected == newestFront, "Removing a back jumped to an unrelated sheet")
model.edit { try $0.restore(newestBack) }
model.pairedPreview = false
model.select(newestBack)
model.navigatePage(by: -1)
precondition(model.selected == newestFront)
print("PASS single-page navigation reaches backs and removal stays on the current sheet")
model.save()
let deadline = Date().addingTimeInterval(20)
while model.exporting && Date() < deadline {
  RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
precondition(!model.exporting && model.pages.isEmpty && model.failure == nil)
precondition(PDFDocument(url: model.lastExport!)?.pageCount == 4)
precondition(!model.scanner.listening && !model.filing.busy)
print(
  "PASS native document workflow: paired selection, rotate/remove/restore, append, PDF save; no scanner or provider contacted"
)

let bitmap = NSBitmapImageRep(
  bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 600,
  bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
memset(bitmap.bitmapData!, 255, bitmap.bytesPerRow * bitmap.pixelsHigh)
let blank = model.root.appendingPathComponent("blank-back.png")
try bitmap.representation(using: .png, properties: [:])!.write(to: blank)
model.skipBlanks = true
try model.scanner.onBegin?(ScanOptions(duplex: true))
try model.scanner.onPage?(blank, 300)
try model.scanner.onPage?(blank, 300)
model.scanner.onEnd?(true, nil)
precondition(model.pages.isEmpty && model.hasRemovedPages && model.sheets.isEmpty)
let skipped = model.store!.draft.pages.last!
precondition(skipped.blankSkipped == true && model.sheetPreviews.isEmpty)
model.edit { try $0.restore(skipped.id) }
model.edit { try $0.restoreLastRemoved() }
precondition(model.pages.count == 2 && !model.hasRemovedPages && model.sheetPreviews.count == 2)
model.save()
let blankDeadline = Date().addingTimeInterval(20)
while model.exporting && Date() < blankDeadline {
  RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
precondition(!model.exporting && model.pages.isEmpty && model.failure == nil)
precondition(PDFDocument(url: model.lastExport!)?.pageCount == 2)
model.choosePaperMode(.longPaper)
model.chooseSides(true)
precondition(!model.duplex && !model.canScanBothSides)
model.choosePaperMode(.automatic)
precondition(
  model.canScanBothSides && model.duplex, "Supported paper must restore the preferred sides")
model.chooseSides(false)
model.choosePaperMode(.longPaper)
model.choosePaperMode(.standard)
precondition(!model.duplex, "An explicit One choice must remain One")
model.chooseSides(true)
precondition(model.skippedPageCount == 0)
print(
  "PASS all-blank app capture shows recoverable state, restores both pages, and enforces paper/sides transitions"
)

let suite = "PaperIn-Preferences-\(UUID())"
let preferences = UserDefaults(suiteName: suite)!
defer { preferences.removePersistentDomain(forName: suite) }
precondition(!AppModel.savedSkipBlanks(in: preferences))
precondition(AppModel.savedPaperMode(in: preferences) == .standard)
preferences.set(true, forKey: "skipBlankBacks")
precondition(AppModel.savedSkipBlanks(in: preferences))
preferences.set(false, forKey: "skipBlanks")
precondition(!AppModel.savedSkipBlanks(in: preferences))
preferences.set("automatic", forKey: "paperMode")
precondition(AppModel.savedPaperMode(in: preferences) == .automatic)
preferences.set("standard", forKey: "paperMode")
precondition(AppModel.savedPaperMode(in: preferences) == .standard)
preferences.set("unknown-mode", forKey: "paperMode")
precondition(AppModel.savedPaperMode(in: preferences) == .standard)
print(
  "PASS absent and legacy preferences preserve off; explicit blank and paper choices survive loading"
)

// Reordering changes the PDF's page order, so show that order instead of paired groups.
model.scan()
model.scan()
let order = model.pages.map(\.id)
precondition(order.count == 4)
model.pairedPreview = true
model.select(order[2])
model.moveSelectedPage(by: -1)
precondition(
  !model.pairedPreview && model.pages.map(\.id) == [order[0], order[2], order[1], order[3]])
precondition(model.selected == order[2])
print("PASS page movement displays the actual PDF order while preserving selection")

// A legacy page that cannot be cropped must not hide the recovered document.
let manifest = model.store!.folder.appendingPathComponent("manifest.json")
var legacy = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as! [String: Any]
var legacyPages = legacy["pages"] as! [[String: Any]]
for index in legacyPages.indices { legacyPages[index].removeValue(forKey: "cropReviewed") }
legacy["pages"] = legacyPages
try JSONSerialization.data(withJSONObject: legacy).write(to: manifest)
let brokenSource = model.store!.folder.appendingPathComponent("sources/\(model.pages.last!.source)")
try Data("synthetic damaged image".utf8).write(to: brokenSource)
model.selected = order[0]
model.restoreDraft(autoCrop: true)
precondition(model.pages.count == 4 && model.canEdit && model.failure != nil)
model.select(order[0])
precondition(model.preview != nil, "Healthy recovered pages must still be usable")
print("PASS startup crop failure preserves visible legacy pages and healthy previews")

// Mount the real settings view: loading a saved provider must not clear its model.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
model.filing.settings.provider = "openaiAPI"
model.filing.settings.model = "synthetic-saved-model"
let window = NSWindow(
  contentRect: NSRect(x: -3000, y: 0, width: 620, height: 800),
  styleMask: [.titled], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
window.contentView = NSHostingView(rootView: FilingSettingsView(filing: model.filing))
window.orderBack(nil)
let renderDeadline = Date().addingTimeInterval(1)
while Date() < renderDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
func fieldValues(_ view: NSView) -> [String] {
  let current = (view as? NSTextField).map { [$0.stringValue] } ?? []
  return current + view.subviews.flatMap(fieldValues)
}
precondition(fieldValues(window.contentView!).contains("synthetic-saved-model"))
window.orderOut(nil)
print("PASS opening AI settings keeps the saved provider model in the actual text field")
model.filing.stop()
model.scanner.pause()
try FileManager().removeItem(at: model.root)

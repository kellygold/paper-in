import AppKit
import PDFKit

precondition(CommandLine.arguments.contains("--demo"))
let model = AppModel()
model.duplex = true
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
precondition(model.canScanBothSides)
model.duplex = true
precondition(model.skippedPageCount == 0)
try FileManager().removeItem(at: model.root)
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

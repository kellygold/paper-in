import AppKit
import PDFKit

precondition(CommandLine.arguments.contains("--demo"))
let model = AppModel()
precondition(
  model.demo && model.pages.count == 2 && model.sheets.count == 1
    && model.selectedSheet?.paired == true)
let back = model.pages[1].id
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
model.skipBlankBacks = true
try model.scanner.onBegin?(ScanOptions(duplex: true))
try model.scanner.onPage?(blank, 300)
try model.scanner.onPage?(blank, 300)
model.scanner.onEnd?(true, nil)
precondition(model.pages.count == 1 && model.hasRemovedPages && model.sheets.count == 1)
let skipped = model.selectedSheet!.page(side: 1)!
precondition(skipped.blankBackSkipped == true && model.sheetPreviews.count == 1)
model.edit { try $0.restore(skipped.id) }
precondition(model.pages.count == 2 && !model.hasRemovedPages && model.sheetPreviews.count == 2)
model.save()
let blankDeadline = Date().addingTimeInterval(20)
while model.exporting && Date() < blankDeadline {
  RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
precondition(!model.exporting && model.pages.isEmpty && model.failure == nil)
precondition(PDFDocument(url: model.lastExport!)?.pageCount == 2)
print(
  "PASS app callbacks skip a blank back, update paired previews, restore that exact side and export both pages"
)

// A crease-like mark triggers a suggestion, which must never remove a PDF page.
for x in 0..<400 {
  for y in 299...300 {
    let offset = y * bitmap.bytesPerRow + x * 3
    for c in 0..<3 { bitmap.bitmapData![offset + c] = 240 }
  }
}
let creased = model.root.appendingPathComponent("creased-back.png")
try bitmap.representation(using: .png, properties: [:])!.write(to: creased)
try model.scanner.onBegin?(ScanOptions(duplex: true))
try model.scanner.onPage?(blank, 300)
try model.scanner.onPage?(creased, 300)
model.scanner.onEnd?(true, nil)
let possible = model.selectedSheet!.page(side: 1)!
precondition(possible.possibleBlankBack == true && !possible.removed)
precondition(model.pages.count == 2 && model.sheetPreviews.count == 2)
model.edit { try $0.remove(possible.id) }
precondition(model.pages.count == 1 && model.sheetPreviews.count == 1)
model.edit { try $0.restore(possible.id) }
precondition(model.pages.count == 2 && model.selectedSheet!.page(side: 1)!.possibleBlankBack == nil)
model.save()
let possibleDeadline = Date().addingTimeInterval(20)
while model.exporting && Date() < possibleDeadline {
  RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
precondition(!model.exporting && model.failure == nil)
precondition(PDFDocument(url: model.lastExport!)?.pageCount == 2)
try FileManager().removeItem(at: model.root)
print("PASS possible-blank capture keeps both previews, exact removal/restoration and both exported sides")

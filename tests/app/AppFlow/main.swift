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
try FileManager().removeItem(at: model.root)
print(
  "PASS native document workflow: paired selection, rotate/remove/restore, append, PDF save; no scanner or provider contacted"
)

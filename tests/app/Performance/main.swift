import AppKit
import Foundation
import PDFKit
import SwiftUI

precondition(CommandLine.arguments.contains("--demo"))
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let model = AppModel()
let window = NSWindow(
  contentRect: NSRect(x: -3000, y: 0, width: 1060, height: 800),
  styleMask: [.titled], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
window.contentView = NSHostingView(rootView: ContentView(model: model, scanner: model.scanner))
window.orderBack(nil)
defer { window.orderOut(nil) }
let fm = FileManager()
defer {
  model.filing.stop()
  model.scanner.pause()
  try? fm.removeItem(at: model.root)
}
func fixture(_ name: String, width: Int, height: Int) throws -> URL {
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  memset(bitmap.bitmapData!, 245, bitmap.bytesPerRow * bitmap.pixelsHigh)
  // Stripes make rotations/crops visible; all content is synthetic.
  for y in stride(from: 100, to: height - 100, by: 250) {
    memset(bitmap.bitmapData! + y * bitmap.bytesPerRow, 35, bitmap.bytesPerRow * 5)
  }
  let file = model.root.appendingPathComponent(name)
  try bitmap.representation(using: .png, properties: [:])!.write(to: file)
  return file
}
let a4 = try fixture("a4.png", width: 2480, height: 3508)
let long = try fixture("long.png", width: 2480, height: 7000)
var lastTick = Date()
var maxGap = 0.0
let timer = Timer.scheduledTimer(withTimeInterval: 0.005, repeats: true) { _ in
  let now = Date()
  maxGap = max(maxGap, now.timeIntervalSince(lastTick) * 1000)
  lastTick = now
}
defer { timer.invalidate() }
func wait(_ busy: () -> Bool) {
  let deadline = Date().addingTimeInterval(120)
  while busy() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
  precondition(!busy(), "Operation timed out")
}
func resetHeartbeat() {
  lastTick = Date()
  maxGap = 0
}
var reports: [[String: Any]] = []
for count in [5, 10, 15] {
  model.startOver()
  // Pair sheets, including an odd final front, with alternating full-size A4 and long pages.
  for index in 0..<count {
    if index % 2 == 0 { try model.store!.beginCapture(expectedSides: 2) }
    try model.store!.ingest(index % 3 == 0 ? long : a4, dpi: 300)
    if index % 2 == 1 || index == count - 1 { try model.store!.completeCapture(success: true) }
  }
  model.refresh()
  wait { model.previewLoading }
  resetHeartbeat()
  var dispatchTimes: [Double] = []
  var completionTimes: [Double] = []
  for page in model.pages {
    let start = Date()
    model.select(page.id)
    dispatchTimes.append(Date().timeIntervalSince(start) * 1000)
    wait { model.previewLoading }
    completionTimes.append(Date().timeIntervalSince(start) * 1000)
    precondition(model.selected == page.id && model.preview != nil)
  }
  // Burst clicks must never publish an older selection over the latest one.
  for page in model.pages.reversed() { model.select(page.id) }
  wait { model.previewLoading }
  precondition(model.selected == model.pages.first!.id && model.preview != nil)
  let removed = model.pages.last!.id
  model.select(removed)
  wait { model.previewLoading }
  let startRemove = Date()
  model.edit { try $0.remove(removed) }
  let removal = Date().timeIntervalSince(startRemove) * 1000
  wait { model.previewLoading }
  precondition(model.pages.count == count - 1)
  model.edit { try $0.restore(removed) }
  model.select(removed)
  wait { model.previewLoading }
  let before = model.preview!.size
  model.edit { try $0.rotate(removed) }
  wait { model.previewLoading }
  precondition(
    model.preview!.size.width == before.height && model.preview!.size.height == before.width)
  let navigationGap = maxGap
  resetHeartbeat()
  let saveStart = Date()
  model.save()
  precondition(model.exporting && !model.canEdit)
  model.startOver()  // Cannot discard while a save owns the store.
  wait { model.exporting }
  let saveMS = Date().timeIntervalSince(saveStart) * 1000
  precondition(model.pages.isEmpty && model.failure == nil)
  let output = model.lastExport!
  precondition(PDFDocument(url: output)?.pageCount == count)
  // Full resolution exports retain original physical page dimensions.
  let first = PDFDocument(url: output)!.page(at: 0)!.bounds(for: .mediaBox)
  precondition(abs(first.height - 7000.0 * 72 / 300) < 1)
  let reopened = try DraftStore(root: model.root)
  precondition(reopened.visiblePages.isEmpty)
  reports.append([
    "pages": count, "selection_dispatch_ms": dispatchTimes,
    "selection_complete_ms": completionTimes, "remove_dispatch_ms": removal,
    "navigation_max_heartbeat_gap_ms": navigationGap, "save_ms": saveMS,
    "save_max_heartbeat_gap_ms": maxGap, "pdf_pages": count,
  ])
}
// Large filing history must load off the main thread without publishing unchanged lists.
let historyRoot = model.root.appendingPathComponent("synthetic-history")
let jobs = historyRoot.appendingPathComponent("filing/jobs")
for index in 0..<1000 {
  let id = UUID().uuidString
  let folder = jobs.appendingPathComponent(id)
  try fm.createDirectory(at: folder, withIntermediateDirectories: true)
  let job = FilingJob(
    id: id, created: String(format: "%08d", index), state: "review",
    original: a4.path, root: historyRoot.path, proposal: nil, error: nil, target: nil)
  try JSONEncoder().encode(job).write(to: folder.appendingPathComponent("job.json"))
}
resetHeartbeat()
let historyStart = Date()
let history = FilingController(root: historyRoot, demo: false)
let historyDispatch = Date().timeIntervalSince(historyStart) * 1000
wait { history.jobs.count != 1000 }
let historyComplete = Date().timeIntervalSince(historyStart) * 1000
let historyGap = maxGap
precondition(history.jobs.allSatisfy { $0.fileMissing == false })
try fm.removeItem(at: a4)
history.refresh()
wait { !history.jobs.allSatisfy { $0.fileMissing == true } }
reports.append([
  "history_jobs": 1000, "refresh_dispatch_ms": historyDispatch,
  "refresh_complete_ms": historyComplete, "history_max_heartbeat_gap_ms": historyGap,
  "external_deletion_detected": true,
])
history.stop()
let json = try JSONSerialization.data(
  withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
print(String(data: json, encoding: .utf8)!)

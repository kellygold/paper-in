import Combine
import Foundation

final class FakeBackend: ScannerBackend {
  var state = ScannerSnapshot(
    name: "Contract fixture", message: "Paused", connected: false, busy: false, listening: false,
    capabilities: ScannerCapabilities(duplex: true, resolutions: [300]))
  let subject = PassthroughSubject<Void, Never>()
  var snapshot: ScannerSnapshot { state }
  var changes: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }
  let diagnostics: Diagnostics
  var onCaptureBegan: ((ScanOptions) throws -> Void)?
  var onImage: ((CapturedImage) throws -> Void)?
  var onCaptureEnded: ((Bool, String?) -> Void)?
  var requested: [ScanOptions] = []
  init(_ root: URL) { diagnostics = Diagnostics(directory: root) }
  func connect() {
    state.connected = true
    state.listening = true
    state.message = "Ready"
    subject.send()
  }
  func pause() {
    state.connected = false
    state.listening = false
    subject.send()
  }
  func retry() { connect() }
  func scan(options: ScanOptions) {
    guard state.connected, !state.busy else { return }
    requested.append(options)
    state.busy = true
    do {
      try onCaptureBegan?(options)
      try onImage?(CapturedImage(url: URL(fileURLWithPath: "/synthetic/front.jpg"), dpi: 300))
      if options.duplex {
        try onImage?(CapturedImage(url: URL(fileURLWithPath: "/synthetic/back.jpg"), dpi: 300))
      }
      state.busy = false
      onCaptureEnded?(true, nil)
    } catch {
      state.busy = false
      onCaptureEnded?(false, "Consumer could not save page")
    }
    subject.send()
  }
}
let root = FileManager().temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager().removeItem(at: root) }
let fake = FakeBackend(root)
let session = ScannerSession(backend: fake)
var images: [String] = []
var outcome = false
var began = false
session.onBegin = { options in began = options.duplex }
session.onPage = { image, _ in images.append(image.lastPathComponent) }
session.onEnd = { success, _ in outcome = success }
session.connect()
session.duplex = true
session.scan()
precondition(
  session.connected && session.supportsDuplex && began && outcome
    && images == ["front.jpg", "back.jpg"])
print("PASS shared session forwards capabilities, options and ordered page delivery")
images = []
session.onPage = { _, _ in throw PaperError("Injected storage failure") }
session.scan()
precondition(!outcome && !session.busy)
session.pause()
precondition(!session.connected)
print("PASS backend reports consumer failure and shared session can pause")

let replacement = FakeBackend(root)
fake.state.busy = true
session.replaceBackend(replacement)
precondition(fake.onImage != nil && replacement.onImage == nil)
fake.state.busy = false
session.replaceBackend(replacement)
precondition(fake.onImage == nil && fake.onCaptureBegan == nil && fake.onCaptureEnded == nil)
images = []
session.onPage = { image, _ in images.append(image.lastPathComponent) }
session.connect()
session.scan()
precondition(outcome && images == ["front.jpg", "back.jpg"] && replacement.requested.count == 1)
print(
  "PASS switching transport refuses busy capture and preserves shared draft callbacks when idle")

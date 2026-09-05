import Combine
import Foundation

enum ScanPaperMode: String, CaseIterable, Identifiable {
  case automatic, standard, longPaper
  var id: String { rawValue }
  var title: String {
    switch self {
    case .automatic: return "Auto"
    case .standard: return "A4"
    case .longPaper: return "Long receipt"
    }
  }
}

struct ScanOptions: Equatable {
  var duplex = false
  var dpi = 300
  var paperMode: ScanPaperMode = .standard
}
struct ScannerCapabilities: Equatable {
  var duplex: Bool
  var resolutions: [Int]
  var paperModes: [ScanPaperMode] = [.standard]
  var duplexPaperModes: [ScanPaperMode] = [.standard]

  func supportsDuplex(for mode: ScanPaperMode) -> Bool {
    duplex && duplexPaperModes.contains(mode)
  }
}
struct ScannerSnapshot {
  var name: String
  var message: String
  var connected: Bool
  var busy: Bool
  var listening: Bool
  var capabilities: ScannerCapabilities
}
struct CapturedImage {
  var url: URL
  var dpi: Double
}

/// Implement this contract to add acquisition hardware. The backend owns transport;
/// the shared session owns the UI-facing state. A throwing image callback means the
/// consumer did not durably accept the page: the backend must stop and preserve it.
protocol ScannerBackend: AnyObject {
  var snapshot: ScannerSnapshot { get }
  var changes: AnyPublisher<Void, Never> { get }
  var diagnostics: Diagnostics { get }
  var onCaptureBegan: ((ScanOptions) throws -> Void)? { get set }
  var onImage: ((CapturedImage) throws -> Void)? { get set }
  var onCaptureEnded: ((Bool, String?) -> Void)? { get set }
  func connect()
  func pause()
  func retry()
  func scan(options: ScanOptions)
}

/// One session drives every scanner UI, regardless of backend or device vendor.
final class ScannerSession: ObservableObject {
  @Published private(set) var state: ScannerSnapshot
  private var backend: any ScannerBackend
  private var subscription: AnyCancellable?
  var onBegin: ((ScanOptions) throws -> Void)?
  var onPage: ((URL, Double) throws -> Void)?
  var onEnd: ((Bool, String?) -> Void)?
  var duplex = false
  var paperMode: ScanPaperMode = .standard
  var paperModes: [ScanPaperMode] { state.capabilities.paperModes }
  func supportsDuplex(for mode: ScanPaperMode) -> Bool {
    state.capabilities.supportsDuplex(for: mode)
  }
  var message: String { state.message }
  var scannerName: String { state.name }
  var connected: Bool { state.connected }
  var busy: Bool { state.busy }
  var listening: Bool { state.listening }
  var supportsDuplex: Bool { state.capabilities.duplex }
  let buttonObserved = false
  var diagnostics: Diagnostics { backend.diagnostics }
  init(backend: any ScannerBackend) {
    self.backend = backend
    state = backend.snapshot
    bindBackend()
  }
  /// Switch transport without replacing the shared session or touching the draft.
  func replaceBackend(_ next: any ScannerBackend) {
    guard !backend.snapshot.busy else { return }
    backend.pause()
    backend.onCaptureBegan = nil
    backend.onImage = nil
    backend.onCaptureEnded = nil
    subscription = nil
    backend = next
    bindBackend()
    refresh()
  }
  private func bindBackend() {
    subscription = backend.changes.receive(on: DispatchQueue.main).sink { [weak self] _ in
      self?.refresh()
    }
    backend.onCaptureBegan = { [weak self] options in try self?.onBegin?(options) }
    backend.onImage = { [weak self] image in try self?.onPage?(image.url, image.dpi) }
    backend.onCaptureEnded = { [weak self] success, error in
      self?.onEnd?(success, error)
      self?.refresh()
    }
  }
  private func refresh() { state = backend.snapshot }
  func connect() {
    backend.connect()
    refresh()
  }
  func pause() {
    backend.pause()
    refresh()
  }
  func retry() {
    backend.retry()
    refresh()
  }
  func scan() {
    backend.scan(options: ScanOptions(duplex: duplex, paperMode: paperMode))
    refresh()
  }
}

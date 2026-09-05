import Combine
import Foundation

/// Shared job lifecycle for USB-proxied and network eSCL scanners.
final class ESCLScannerBackend: NSObject, ObservableObject, ScannerBackend {
  private let profile: any ESCLScannerProfile
  private let connection: ScannerConnection
  private let discovery: any ScannerDiscovery
  private let makeClient: (URL) -> ESCLClient
  var changes: AnyPublisher<Void, Never> { objectWillChange.eraseToAnyPublisher() }
  var snapshot: ScannerSnapshot {
    ScannerSnapshot(
      name: profile.name, message: message, connected: connected, busy: busy, listening: listening,
      capabilities: capabilities)
  }
  @Published private(set) var message = "Scanner paused"
  @Published private(set) var connected = false
  @Published private(set) var busy = false
  @Published private(set) var listening = false
  private var capabilities = ScannerCapabilities(duplex: false, resolutions: [300])
  var supportsDuplex: Bool { capabilities.duplex }
  let buttonObserved = false
  var onCaptureBegan: ((ScanOptions) throws -> Void)?
  var onImage: ((CapturedImage) throws -> Void)?
  var onCaptureEnded: ((Bool, String?) -> Void)?
  let diagnostics: Diagnostics
  private let staging: URL
  private var client: ESCLClient?
  private var timer: Timer?
  private var generation = UUID()
  private var stopping = false
  init(
    staging: URL, profile: any ESCLScannerProfile, connection: ScannerConnection,
    discovery: (any ScannerDiscovery)? = nil,
    makeClient: @escaping (URL) -> ESCLClient = { ESCLClient(base: $0) }
  ) {
    self.staging = staging
    self.profile = profile
    self.connection = connection
    self.discovery = discovery ?? BonjourScannerDiscovery(connection: connection)
    self.makeClient = makeClient
    diagnostics = Diagnostics(
      directory: staging.deletingLastPathComponent().appendingPathComponent("Diagnostics"))
    super.init()
  }
  func connect() {
    guard !listening, !busy else { return }
    generation = UUID()
    listening = true
    message = "Looking for your \(connection.title) scanner…"
    diagnostics.event("discovery_started", ["connection": connection.rawValue])
    let token = generation
    discovery.start(
      matching: { [profile] in profile.matchesService($0) },
      onEndpoint: { [weak self] endpoint in
        guard let self, self.listening, self.generation == token else { return }
        self.resolved(endpoint: endpoint)
      },
      onError: { [weak self] error in
        guard let self, self.generation == token else { return }
        self.pause()
        self.message = error.localizedDescription
      })
    timer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
      guard let self, !self.connected else { return }
      self.pause()
      self.message =
        self.connection == .usb
        ? "USB scanner wasn’t found. Check its power and cable, then click Connect."
        : "Wi-Fi scanner wasn’t found. Put the scanner in Wi-Fi mode and connect it to the same network as this Mac."
    }
  }
  func retry() {
    if !busy {
      pause()
      connect()
    }
  }
  func pause() {
    if busy {
      stopping = true
      message = "Stopping after the current transfer; completed pages will be saved."
      return
    }
    generation = UUID()
    timer?.invalidate()
    stopDiscovery()
    client = nil
    connected = false
    listening = false
    message = "Scanner paused"
  }
  private func stopDiscovery() { discovery.stop() }
  private func resolved(endpoint: ScannerEndpoint) {
    guard client == nil else { return }
    diagnostics.event("service_resolved", ["connection": connection.rawValue])
    let token = generation
    let client = makeClient(endpoint.base)
    self.client = client
    // DNS callbacks finish before their references are released.
    DispatchQueue.main.async { [weak self] in
      guard let self, self.generation == token else { return }
      self.stopDiscovery()
    }
    Task { @MainActor in
      do {
        let caps = try await client.xml("ScannerCapabilities")
        guard self.generation == token else { return }
        guard self.profile.matchesCapabilities(caps) else {
          throw PaperError("The endpoint did not identify as \(self.profile.name).")
        }
        self.capabilities = self.profile.capabilities(from: caps)
        self.connected = true
        self.timer?.invalidate()
        self.message = "Ready over \(self.connection.title) — insert a sheet and press Scan"
        self.diagnostics.event("scanner_connected", ["connection": self.connection.rawValue])
      } catch {
        guard self.generation == token else { return }
        self.pause()
        self.message = error.localizedDescription
      }
    }
  }
  func scan(options: ScanOptions) {
    guard connected, listening, !busy, let client else { return }
    guard profile.resolutions.contains(options.dpi) else {
      message =
        "Choose a supported resolution: \(profile.resolutions.map(String.init).joined(separator: ", ")) dpi."
      return
    }
    guard capabilities.paperModes.contains(options.paperMode) else {
      message =
        "This connection does not advertise support for the selected paper size. Choose A4 or reconnect."
      return
    }
    guard !options.duplex || capabilities.supportsDuplex(for: options.paperMode) else {
      message =
        "This paper size supports one side at a time. Choose One under Sides before scanning."
      return
    }
    busy = true
    stopping = false
    let twoSides = options.duplex
    message = "Checking the scanner…"
    Task { @MainActor in
      var ownedJob: URL?
      var began = false
      var received = 0
      var failure: String?
      do {
        let status = try await client.xml("ScannerStatus")
        let state = status.values["State"]?.first ?? "Unknown"
        let feeder = status.values["AdfState"]?.first ?? "Unknown"
        self.diagnostics.event("scanner_status", ["state": state, "feeder": feeder])
        guard !self.stopping else { throw PaperError("Scan stopped before starting.") }
        guard state == "Idle" else {
          throw PaperError(
            "Scanner reports \(state). Check its fault light and jam cover, then retry.")
        }
        guard feeder == "ScannerAdfLoaded" else {
          if feeder == "ScannerAdfJam" {
            throw PaperError(
              "Scanner reports a paper jam. Open the top cover, remove the sheet, and close the cover. If the fault light is off but this persists, restart the scanner."
            )
          }
          if feeder == "ScannerAdfEmpty" {
            throw PaperError("No paper is loaded. Insert a sheet, then reconnect and scan.")
          }
          throw PaperError("Scanner reports \(feeder). Check its fault light and paper path.")
        }
        let folder = self.staging.appendingPathComponent(UUID().uuidString)
        try FileManager().createDirectory(at: folder, withIntermediateDirectories: true)
        try self.onCaptureBegan?(options)
        began = true
        self.message = "Scanning…"
        self.diagnostics.event(
          "scan_requested",
          ["duplex": twoSides, "dpi": options.dpi, "paper_mode": options.paperMode.rawValue])
        let job = try await client.create(
          settings: self.profile.settings(options: options))
        ownedJob = job
        self.diagnostics.event("scan_accepted", ["http_status": 201])
        for index in 0..<(twoSides ? 2 : 1) {
          if index > 0 && self.stopping {
            throw PaperError("Stopped after the front side. Completed pages are saved.")
          }
          let page = folder.appendingPathComponent("page-\(index + 1).jpg")
          try await client.page(job, to: page)
          try self.onImage?(CapturedImage(url: page, dpi: Double(options.dpi)))
          received += 1
          self.diagnostics.event("page_saved", ["received_files": received])
        }
      } catch {
        failure = error.localizedDescription
        self.diagnostics.event("scan_failed", error: error)
      }
      if let job = ownedJob {
        do { try await client.close(job) } catch {
          failure =
            (failure.map { $0 + " " } ?? "")
            + "Pages are preserved, but the scanner job did not close: \(error.localizedDescription)"
        }
      }
      self.busy = false
      if began { self.onCaptureEnded?(failure == nil && received > 0, failure) }
      if failure != nil || self.stopping { self.pause() }
      self.message =
        failure
        ?? (self.stopping
          ? "Scanner paused. Completed pages are saved."
          : "Page saved — add another sheet or Save PDF")
    }
  }
}

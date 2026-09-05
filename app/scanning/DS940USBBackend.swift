import Combine
import Foundation
import dnssd

final class DS940USBBackend: NSObject, ObservableObject, ScannerBackend {
  private let profile = DS940Profile()
  var changes: AnyPublisher<Void, Never> { objectWillChange.eraseToAnyPublisher() }
  var snapshot: ScannerSnapshot {
    ScannerSnapshot(
      name: profile.name, message: message, connected: connected, busy: busy, listening: listening,
      capabilities: ScannerCapabilities(duplex: supportsDuplex, resolutions: [300]))
  }
  @Published private(set) var message = "Scanner paused"
  @Published private(set) var connected = false
  @Published private(set) var busy = false
  @Published private(set) var listening = false
  @Published private(set) var supportsDuplex = false
  let buttonObserved = false
  var onCaptureBegan: ((ScanOptions) throws -> Void)?
  var onImage: ((CapturedImage) throws -> Void)?
  var onCaptureEnded: ((Bool, String?) -> Void)?
  let diagnostics: Diagnostics
  private let staging: URL
  private var browseRef: DNSServiceRef?
  private var resolveRef: DNSServiceRef?
  private var client: ESCLClient?
  private var timer: Timer?
  private var generation = UUID()
  private var stopping = false
  init(staging: URL) {
    self.staging = staging
    diagnostics = Diagnostics(
      directory: staging.deletingLastPathComponent().appendingPathComponent("Diagnostics"))
    super.init()
  }
  func connect() {
    guard !listening, !busy else { return }
    generation = UUID()
    listening = true
    message = "Looking for your USB scanner…"
    diagnostics.event("usb_discovery_started")
    let context = Unmanaged.passUnretained(self).toOpaque()
    let result = DNSServiceBrowse(
      &browseRef, 0, kDNSServiceInterfaceIndexLocalOnly, "_ippusb._tcp", "local.",
      { _, flags, interface, error, name, type, domain, context in
        guard let context, let name, let type, let domain else { return }
        let owner = Unmanaged<DS940USBBackend>.fromOpaque(context).takeUnretainedValue()
        guard error == 0, flags & kDNSServiceFlagsAdd != 0, owner.listening,
          owner.resolveRef == nil,
          owner.profile.matchesService(String(cString: name))
        else { return }
        owner.diagnostics.event("usb_service_found")
        let code = DNSServiceResolve(
          &owner.resolveRef, 0, interface, name, type, domain,
          { _, _, _, error, _, host, port, _, _, context in
            guard let context, let host else { return }
            let owner = Unmanaged<DS940USBBackend>.fromOpaque(context).takeUnretainedValue()
            guard error == 0, owner.listening,
              ["localhost.", "localhost", "localhost.local."].contains(String(cString: host))
            else { return }
            owner.resolved(port: Int(UInt16(bigEndian: port)))
          }, context)
        if code == 0, let ref = owner.resolveRef {
          DNSServiceSetDispatchQueue(ref, DispatchQueue.main)
        } else {
          owner.diagnostics.event("usb_resolution_failed", ["code": code])
        }
      }, context)
    guard result == 0, let ref = browseRef else {
      pause()
      message = "USB discovery failed (\(result))."
      return
    }
    DNSServiceSetDispatchQueue(ref, DispatchQueue.main)
    timer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
      guard let self, !self.connected else { return }
      self.pause()
      self.message = "USB scanner wasn’t found. Check its power and cable, then click Connect."
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
  private func stopDiscovery() {
    if let ref = browseRef {
      DNSServiceRefDeallocate(ref)
      browseRef = nil
    }
    if let ref = resolveRef {
      DNSServiceRefDeallocate(ref)
      resolveRef = nil
    }
  }
  private func resolved(port: Int) {
    guard port > 0, client == nil else { return }
    diagnostics.event("usb_service_resolved", ["port": port])
    let token = generation
    let client = ESCLClient(base: URL(string: "http://localhost:\(port)/eSCL")!)
    self.client = client
    // Deallocate on the same queue after the DNS callback has returned.
    DispatchQueue.main.async { [weak self] in self?.stopDiscovery() }
    Task { @MainActor in
      do {
        let caps = try await client.xml("ScannerCapabilities")
        guard self.generation == token else { return }
        guard self.profile.matchesCapabilities(caps) else {
          throw PaperError("The USB endpoint did not identify as your DS-940DW.")
        }
        self.supportsDuplex = caps.values["AdfOption"]?.contains("Duplex") == true
        self.connected = true
        self.timer?.invalidate()
        self.message = "Ready — insert a sheet and press Scan"
        self.diagnostics.event("usb_connected", ["port": port])
      } catch {
        guard self.generation == token else { return }
        self.pause()
        self.message = error.localizedDescription
      }
    }
  }
  func scan(options: ScanOptions) {
    guard connected, listening, !busy, let client else { return }
    guard options.dpi == 300 else {
      message = "This scanner profile currently supports 300 dpi."
      return
    }
    busy = true
    stopping = false
    let twoSides = options.duplex && supportsDuplex
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
        self.diagnostics.event("usb_status", ["state": state, "feeder": feeder])
        guard !self.stopping else { throw PaperError("Scan stopped before starting.") }
        guard state == "Idle" else {
          throw PaperError(
            "Scanner reports \(state). Check its fault light and jam cover, then retry.")
        }
        guard feeder == "ScannerAdfLoaded" else {
          throw PaperError(
            "Scanner reports \(feeder). Reinsert the sheet and check its fault light.")
        }
        let folder = self.staging.appendingPathComponent(UUID().uuidString)
        try FileManager().createDirectory(at: folder, withIntermediateDirectories: true)
        try self.onCaptureBegan?(ScanOptions(duplex: twoSides))
        began = true
        self.message = "Scanning…"
        self.diagnostics.event("usb_scan_requested", ["duplex": twoSides, "dpi": 300])
        let job = try await client.create(
          settings: self.profile.settings(options: ScanOptions(duplex: twoSides)))
        ownedJob = job
        self.diagnostics.event("usb_scan_accepted", ["http_status": 201])
        for index in 0..<(twoSides ? 2 : 1) {
          if index > 0 && self.stopping {
            throw PaperError("Stopped after the front side. Completed pages are saved.")
          }
          let page = folder.appendingPathComponent("page-\(index + 1).jpg")
          try await client.page(job, to: page)
          try self.onImage?(CapturedImage(url: page, dpi: 300))
          received += 1
          self.diagnostics.event("page_saved", ["received_files": received])
        }
      } catch {
        failure = error.localizedDescription
        self.diagnostics.event("usb_scan_failed", error: error)
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

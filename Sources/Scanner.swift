import Foundation
import Combine
import ImageCaptureCore

// Every operation goes through this one owner. Discovery begins only on Connect.
final class ScannerController: NSObject, ObservableObject, ICDeviceBrowserDelegate, ICScannerDeviceDelegate {
    @Published private(set) var message = "Scanner paused"
    @Published private(set) var connected = false
    @Published private(set) var busy = false
    @Published private(set) var listening = false
    @Published private(set) var supportsDuplex = false
    @Published private(set) var buttonObserved = false
    @Published private(set) var scannerName = "Brother DS-940DW"
    var duplex = false
    var onBegin: (() throws -> Void)?
    var onPage: ((URL, Double) throws -> Void)?
    var onEnd: ((Bool, String?) -> Void)?
    private var browser: ICDeviceBrowser?
    private var scanner: ICScannerDevice?
    private var opening = false
    private var selecting = false
    private var activeDirectory: URL?
    private var delivered = Set<String>()
    private var jobTimer: Timer?
    private var connectionTimer: Timer?
    private var captureFailed = false
    private var pendingButton = false
    let diagnostics: Diagnostics
    private let staging: URL
    private let defaults: UserDefaults
    private let browserFactory: () -> ICDeviceBrowser

    init(staging: URL, defaults: UserDefaults = UserDefaults(), browserFactory: @escaping () -> ICDeviceBrowser = { ICDeviceBrowser() }) { self.staging = staging; self.defaults = defaults; self.browserFactory = browserFactory; diagnostics = Diagnostics(directory: staging.deletingLastPathComponent().appendingPathComponent("Diagnostics")); super.init() }

    func connect() {
        guard !listening else { return }
        diagnostics.event("discovery_started")
        listening = true; message = "Looking for your scanner…"
        let b = browserFactory(); browser = b; b.delegate = self
        b.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: ICDeviceTypeMask.scanner.rawValue | ICDeviceLocationTypeMask.local.rawValue)!
        b.start()
    }
    func pause() {
        diagnostics.event("scanner_paused", ["was_scanning": busy])
        listening = false; pendingButton = false
        connectionTimer?.invalidate(); jobTimer?.invalidate()
        if busy { scanner?.cancelScan(); finish(false, "Scanning stopped. Completed pages are saved.") }
        connected = false; opening = false; selecting = false
        scanner?.requestCloseSession(); scanner?.delegate = nil; scanner = nil
        browser?.stop(); browser?.delegate = nil; browser = nil
        message = "Scanner paused"
    }
    func retry() {
        guard !busy else { return }
        if let scanner, !opening, !connected { open(scanner) }
        else if !listening { connect() }
    }
    private func identity(_ device: ICDevice) -> String? {
        if let serial = device.serialNumberString, !serial.isEmpty { return "serial:\(serial)" }
        if let uuid = device.uuidString, !uuid.isEmpty { return "uuid:\(uuid)" }
        return nil
    }
    private func open(_ device: ICScannerDevice) {
        guard listening, !opening, !device.hasOpenSession else { return }
        scanner = device; device.delegate = self; opening = true; connected = false
        scannerName = device.name ?? "Brother DS-940DW"; message = "Connecting…"
        connectionTimer?.invalidate()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self, weak device] _ in
            guard let self, let device, self.scanner === device, !self.connected else { return }
            self.pause(); self.message = "Connection timed out. Your pages are saved. Try Connect again."
        }
        diagnostics.event("session_open_requested", ["transport": device.transportType ?? "unknown"])
        device.requestOpenSession()
    }
    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard listening, scanner == nil, let candidate = device as? ICScannerDevice else { return }
        let saved = defaults.string(forKey: "scannerIdentity")
        if let saved { guard identity(device) == saved else { return } }
        else { guard (device.name ?? "").localizedCaseInsensitiveContains("DS-940") else { return } }
        diagnostics.event("selected_scanner_discovered", ["name": candidate.name ?? "unknown"])
        open(candidate)
    }
    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) { removed(device) }
    func didRemove(_ device: ICDevice) { removed(device) }
    private func removed(_ device: ICDevice) {
        guard scanner === device else { return }
        diagnostics.event("device_removed", ["during_scan": busy])
        if busy { finish(false, "Scanner disconnected. Completed pages are saved.") }
        // Stop browsing, too: repeated remove/add events otherwise create an unbounded reconnect loop.
        pause()
        message = "Connection dropped. Your pages are saved. Check the USB connection, then click Connect."
    }
    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        guard scanner === device, listening else { return }
        opening = false
        diagnostics.event("session_open_completed", ["success": error == nil], error: error)
        if let error { pause(); message = "Couldn’t connect: \(error.localizedDescription). Click Connect when you’re ready to retry."; return }
        if let id = identity(device) { defaults.set(id, forKey: "scannerIdentity") }
        selectFeeder()
    }
    func deviceDidBecomeReady(_ device: ICDevice) {
        guard scanner === device, listening, device.hasOpenSession, !connected else { return }
        selectFeeder()
    }
    private func selectFeeder() {
        guard let scanner, scanner.hasOpenSession, !selecting else { return }
        guard scanner.availableFunctionalUnitTypes.contains(NSNumber(value: ICScannerFunctionalUnitType.documentFeeder.rawValue)) else {
            message = "This connection does not expose a document feeder."; connectionTimer?.invalidate(); return
        }
        selecting = true
        scanner.requestSelect(.documentFeeder)
    }
    func scannerDevice(_ scanner: ICScannerDevice, didSelect functionalUnit: ICScannerFunctionalUnit, error: Error?) {
        guard self.scanner === scanner, listening, scanner.hasOpenSession else { return }
        selecting = false
        if let error { message = "Couldn’t prepare scanner: \(error.localizedDescription)"; connectionTimer?.invalidate(); return }
        guard let feeder = functionalUnit as? ICScannerFunctionalUnitDocumentFeeder else { return }
        diagnostics.event("feeder_selected", ["duplex": feeder.supportsDuplexScanning,
            "resolutions": feeder.supportedResolutions.map { $0 },
            "document_types": feeder.supportedDocumentTypes.map { $0 },
            "reported_paper_loaded": feeder.documentLoaded,
            "scan_area": NSStringFromRect(feeder.scanArea), "document_size": NSStringFromSize(feeder.documentSize),
            "physical_size": NSStringFromSize(feeder.physicalSize), "measurement_unit": feeder.measurementUnit.rawValue])
        supportsDuplex = feeder.supportsDuplexScanning
        connected = true; connectionTimer?.invalidate(); message = "Ready — insert a sheet and press Scan"
        if pendingButton { pendingButton = false; scan() }
    }
    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        guard scanner === device else { return }
        diagnostics.event("session_closed", ["during_scan": busy], error: error)
        if busy { finish(false, "Scanner connection closed. Completed pages are saved.") }
        connected = false; opening = false; selecting = false
        if listening { message = "Scanner connection closed. Click Retry to reconnect." }
    }
    func scannerDeviceDidBecomeAvailable(_ scanner: ICScannerDevice) {
        guard self.scanner === scanner, listening, !busy, !connected else { return }
        message = "Scanner is available. Click Retry to connect."
    }
    func deviceBrowser(_ browser: ICDeviceBrowser, requestsSelect device: ICDevice) {
        guard listening, scanner === device else { return }
        diagnostics.event("physical_button_received")
        buttonObserved = true
        if connected { scan() } else { pendingButton = true; retry() }
    }
    // Some drivers deliver this legacy selector despite its absence from the current protocol header.
    @objc(device:didReceiveButtonPress:)
    func receivedButton(_ device: ICDevice, button: NSString) {
        guard scanner === device, listening, button as String == ICButtonTypeScan else { return }
        diagnostics.event("physical_button_received")
        buttonObserved = true; scan()
    }
    func scan() {
        guard listening, connected, !busy, let scanner,
              let feeder = scanner.selectedFunctionalUnit as? ICScannerFunctionalUnitDocumentFeeder else { return }
        do {
            guard feeder.supportedResolutions.contains(300), feeder.supportedBitDepths.contains(8),
                  feeder.supportedDocumentTypes.contains(Int(ICScannerDocumentType.typeA4.rawValue)) else {
                throw PaperError("This connection doesn’t expose the A4 / 300 dpi preset. No scan was started.")
            }
            guard !duplex || feeder.supportsDuplexScanning else { throw PaperError("Two-sided scanning isn’t available on this connection.") }
            // A stale documentLoaded value must not prevent a deliberate manual scan.
            if feeder.supportedMeasurementUnits.contains(Int(ICScannerMeasurementUnit.inches.rawValue)) {
                feeder.measurementUnit = .inches
            }
            feeder.documentType = .typeA4
            feeder.resolution = 300; feeder.pixelDataType = .RGB; feeder.bitDepth = .depth8Bits
            feeder.duplexScanningEnabled = duplex
            // documentType does not guarantee that the driver's scan rectangle is initialized.
            // documentSize is expressed in the functional unit's current measurement units.
            let size = feeder.documentSize
            guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
                throw PaperError("The scanner supplied an empty paper size. No scan was started.")
            }
            feeder.scanArea = NSRect(origin: .zero, size: size)
            let area = feeder.scanArea
            guard area.width > 0, area.height > 0 else {
                throw PaperError("The scanner did not accept a scan area. No scan was started.")
            }
            let dir = staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager().createDirectory(at: dir, withIntermediateDirectories: true)
            try onBegin?()
            activeDirectory = dir; delivered = []; captureFailed = false; busy = true
            scanner.transferMode = .fileBased; scanner.downloadsDirectory = dir
            scanner.documentName = "Page"; scanner.documentUTI = "public.jpeg"
            message = "Scanning… completed pages are saved as they arrive"
            jobTimer?.invalidate()
            jobTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in
                guard let self, self.busy else { return }
                self.pause(); self.message = "Scanner stopped responding. Completed pages are saved. Reconnect before trying the sheet again."
            }
            diagnostics.event("scan_requested", ["job": dir.lastPathComponent, "dpi": feeder.resolution, "duplex": duplex, "reported_paper_loaded": feeder.documentLoaded,
                "scan_area": NSStringFromRect(feeder.scanArea), "document_size": NSStringFromSize(feeder.documentSize),
                "measurement_unit": feeder.measurementUnit.rawValue, "pixel_type": feeder.pixelDataType.rawValue,
                "bit_depth": feeder.bitDepth.rawValue, "image_format": scanner.documentUTI])
            scanner.requestScan()
        } catch { diagnostics.event("scan_not_started", error: error); message = error.localizedDescription }
    }
    func scannerDevice(_ scanner: ICScannerDevice, didScanTo url: URL) {
        guard self.scanner === scanner, busy, let dir = activeDirectory else { return }
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        guard canonical.deletingLastPathComponent() == dir.resolvingSymlinksInPath().standardizedFileURL else {
            diagnostics.event("page_callback_outside_current_job", ["file": url.lastPathComponent])
            return
        }
        guard !delivered.contains(canonical.path) else { return }
        do {
            diagnostics.event("page_received", ["job": dir.lastPathComponent, "file": url.lastPathComponent])
            try onPage?(url, Double(scanner.selectedFunctionalUnit.resolution))
            delivered.insert(canonical.path)
            diagnostics.event("page_saved", ["job": dir.lastPathComponent, "received_files": delivered.count])
        } catch {
            diagnostics.event("page_save_failed", error: error)
            captureFailed = true; scanner.cancelScan()
            message = "Couldn’t save this page: \(error.localizedDescription). Earlier pages are preserved."
        }
    }
    func scannerDevice(_ scanner: ICScannerDevice, didCompleteScanWithError error: Error?) {
        guard self.scanner === scanner, busy else { return }
        diagnostics.event("scan_completed", ["received_files": delivered.count, "save_failed": captureFailed], error: error)
        if captureFailed { finish(false, message) }
        else if let error { finish(false, "Scan interrupted: \(error.localizedDescription). Completed pages are saved.") }
        else if delivered.isEmpty { finish(false, "The scan ended without delivering an image. Your saved pages are preserved; the connection log has the scan details.") }
        else { finish(true, nil) }
    }
    private func finish(_ success: Bool, _ error: String?) {
        jobTimer?.invalidate(); busy = false; activeDirectory = nil
        message = error ?? "Page saved — add another sheet or Save PDF"
        onEnd?(success, error)
    }
    func device(_ device: ICDevice, didEncounterError error: Error?) {
        guard scanner === device else { return }
        // Preserve the job until completion/cancellation; don't start a second uncertain job.
        diagnostics.event("scanner_error", ["during_scan": busy], error: error)
        if let error { message = "Scanner reported: \(error.localizedDescription)" }
    }
}

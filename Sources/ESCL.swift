import Foundation
import Combine
import ImageIO
import dnssd

// Local USB proxy only. Never follow a scanner-supplied redirect to another host.
final class NoScanRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
final class ScanXML: NSObject, XMLParserDelegate {
    var values: [String: [String]] = [:]
    private var text = ""
    static func read(_ data: Data) throws -> ScanXML {
        let result = ScanXML(); let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true; parser.shouldResolveExternalEntities = false; parser.delegate = result
        guard parser.parse() else { throw PaperError("The scanner returned unreadable status information.") }
        return result
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) { text = "" }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { values[elementName, default: []].append(value) }; text = ""
    }
}
final class ESCLClient {
    let base: URL
    let session: URLSession
    init(base: URL, session: URLSession? = nil) {
        self.base = base
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = session ?? URLSession(configuration: config, delegate: NoScanRedirects(), delegateQueue: nil)
    }
    static func settings(duplex: Bool) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <scan:ScanSettings xmlns:scan="http://schemas.hp.com/imaging/escl/2011/05/03" xmlns:pwg="http://www.pwg.org/schemas/2010/12/sm">
        <pwg:Version>2.0</pwg:Version><scan:Intent>Document</scan:Intent>
        <pwg:ScanRegions><pwg:ScanRegion><pwg:ContentRegionUnits>escl:ThreeHundredthsOfInches</pwg:ContentRegionUnits><pwg:XOffset>0</pwg:XOffset><pwg:YOffset>0</pwg:YOffset><pwg:Width>2480</pwg:Width><pwg:Height>3508</pwg:Height></pwg:ScanRegion></pwg:ScanRegions>
        <pwg:InputSource>Feeder</pwg:InputSource><scan:ColorMode>RGB24</scan:ColorMode><pwg:DocumentFormat>image/jpeg</pwg:DocumentFormat><scan:DocumentFormatExt>image/jpeg</scan:DocumentFormatExt><scan:XResolution>300</scan:XResolution><scan:YResolution>300</scan:YResolution><scan:Duplex>\(duplex ? "true" : "false")</scan:Duplex>
        </scan:ScanSettings>
        """.utf8)
    }
    func request(_ url: URL, method: String = "GET", body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body
        if body != nil { request.setValue("text/xml", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw PaperError("No HTTP response from the USB scanner.") }
        return (data, response)
    }
    func xml(_ path: String) async throws -> ScanXML {
        let (data, response) = try await request(base.appendingPathComponent(path))
        guard response.statusCode == 200 else { throw Self.httpError(response.statusCode) }
        return try ScanXML.read(data)
    }
    static func httpError(_ code: Int) -> PaperError {
        let reason: String
        switch code {
        case 409: reason = "Scanner rejected the scan request. Check its fault light and that the jam cover is closed; its settings may also have been rejected."
        case 503: reason = "Scanner reports busy or unavailable. Check its fault light and jam cover before retrying."
        case 403: reason = "Scanner refused access."
        default: reason = "Scanner request failed."
        }
        return PaperError("\(reason) (HTTP \(code))")
    }
    func create(duplex: Bool) async throws -> URL {
        let (_, response) = try await request(base.appendingPathComponent("ScanJobs"), method: "POST", body: Self.settings(duplex: duplex))
        guard response.statusCode == 201 else { throw Self.httpError(response.statusCode) }
        guard let location = response.value(forHTTPHeaderField: "Location"),
              let job = URL(string: location, relativeTo: base.appendingPathComponent("ScanJobs"))?.absoluteURL,
              job.scheme == base.scheme, job.host == base.host, job.port == base.port,
              job.user == nil, job.password == nil, job.query == nil, job.fragment == nil,
              job.path.hasPrefix(base.path + "/ScanJobs/"), !job.path.contains("..") else {
            throw PaperError("Scanner accepted a job but returned an invalid job address. Check the scanner before retrying.")
        }
        return job
    }
    func page(_ job: URL, to url: URL) async throws {
        let (data, response) = try await request(job.appendingPathComponent("NextDocument"))
        guard response.statusCode == 200 else { throw Self.httpError(response.statusCode) }
        // Preserve bytes before decoding, including an incomplete response for diagnostics/recovery.
        try data.write(to: url, options: .withoutOverwriting)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw PaperError("Scanner delivered an incomplete or unreadable image. Earlier pages are saved.")
        }
    }
    func close(_ job: URL) async throws {
        let (_, response) = try await request(job, method: "DELETE")
        guard [200, 204, 404, 410].contains(response.statusCode) else { throw Self.httpError(response.statusCode) }
    }
}

final class USBScannerController: NSObject, ObservableObject {
    @Published private(set) var message = "Scanner paused"
    @Published private(set) var connected = false
    @Published private(set) var busy = false
    @Published private(set) var listening = false
    @Published private(set) var supportsDuplex = false
    let buttonObserved = false
    let scannerName = "Brother DS-940DW"
    var duplex = false
    var onBegin: (() throws -> Void)?
    var onPage: ((URL, Double) throws -> Void)?
    var onEnd: ((Bool, String?) -> Void)?
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
        diagnostics = Diagnostics(directory: staging.deletingLastPathComponent().appendingPathComponent("Diagnostics"))
        super.init()
    }
    func connect() {
        guard !listening, !busy else { return }
        generation = UUID(); listening = true; message = "Looking for your USB scanner…"
        diagnostics.event("usb_discovery_started")
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = DNSServiceBrowse(&browseRef, 0, kDNSServiceInterfaceIndexLocalOnly, "_ippusb._tcp", "local.", { _, flags, interface, error, name, type, domain, context in
            guard let context, let name, let type, let domain else { return }
            let owner = Unmanaged<USBScannerController>.fromOpaque(context).takeUnretainedValue()
            guard error == 0, flags & kDNSServiceFlagsAdd != 0, owner.listening, owner.resolveRef == nil,
                  String(cString: name).localizedCaseInsensitiveContains("DS-940") else { return }
            owner.diagnostics.event("usb_service_found")
            let code = DNSServiceResolve(&owner.resolveRef, 0, interface, name, type, domain, { _, _, _, error, _, host, port, _, _, context in
                guard let context, let host else { return }
                let owner = Unmanaged<USBScannerController>.fromOpaque(context).takeUnretainedValue()
                guard error == 0, owner.listening, ["localhost.", "localhost", "localhost.local."].contains(String(cString: host)) else { return }
                owner.resolved(port: Int(UInt16(bigEndian: port)))
            }, context)
            if code == 0, let ref = owner.resolveRef { DNSServiceSetDispatchQueue(ref, DispatchQueue.main) }
            else { owner.diagnostics.event("usb_resolution_failed", ["code": code]) }
        }, context)
        guard result == 0, let ref = browseRef else { pause(); message = "USB discovery failed (\(result))."; return }
        DNSServiceSetDispatchQueue(ref, DispatchQueue.main)
        timer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
            guard let self, !self.connected else { return }
            self.pause(); self.message = "USB scanner wasn’t found. Check its power and cable, then click Connect."
        }
    }
    func retry() { if !busy { pause(); connect() } }
    func pause() {
        if busy { stopping = true; message = "Stopping after the current transfer; completed pages will be saved."; return }
        generation = UUID(); timer?.invalidate(); stopDiscovery(); client = nil
        connected = false; listening = false; message = "Scanner paused"
    }
    private func stopDiscovery() {
        if let ref = browseRef { DNSServiceRefDeallocate(ref); browseRef = nil }
        if let ref = resolveRef { DNSServiceRefDeallocate(ref); resolveRef = nil }
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
                guard caps.values["MakeAndModel"]?.contains(where: { $0.contains("DS-940") }) == true else { throw PaperError("The USB endpoint did not identify as your DS-940DW.") }
                self.supportsDuplex = caps.values["AdfOption"]?.contains("Duplex") == true
                self.connected = true; self.timer?.invalidate(); self.message = "Ready — insert a sheet and press Scan"
                self.diagnostics.event("usb_connected", ["port": port])
            } catch { guard self.generation == token else { return }; self.pause(); self.message = error.localizedDescription }
        }
    }
    func scan() {
        guard connected, listening, !busy, let client else { return }
        busy = true; stopping = false; let twoSides = duplex && supportsDuplex
        message = "Checking the scanner…"
        Task { @MainActor in
            var ownedJob: URL?; var began = false; var received = 0; var failure: String?
            do {
                let status = try await client.xml("ScannerStatus")
                let state = status.values["State"]?.first ?? "Unknown"
                let feeder = status.values["AdfState"]?.first ?? "Unknown"
                self.diagnostics.event("usb_status", ["state": state, "feeder": feeder])
                guard !self.stopping else { throw PaperError("Scan stopped before starting.") }
                guard state == "Idle" else { throw PaperError("Scanner reports \(state). Check its fault light and jam cover, then retry.") }
                guard feeder == "ScannerAdfLoaded" else { throw PaperError("Scanner reports \(feeder). Reinsert the sheet and check its fault light.") }
                let folder = self.staging.appendingPathComponent(UUID().uuidString)
                try FileManager().createDirectory(at: folder, withIntermediateDirectories: true)
                try self.onBegin?(); began = true
                self.message = "Scanning…"
                self.diagnostics.event("usb_scan_requested", ["duplex": twoSides, "dpi": 300])
                let job = try await client.create(duplex: twoSides); ownedJob = job
                self.diagnostics.event("usb_scan_accepted", ["http_status": 201])
                for index in 0..<(twoSides ? 2 : 1) {
                    if index > 0 && self.stopping { throw PaperError("Stopped after the front side. Completed pages are saved.") }
                    let page = folder.appendingPathComponent("page-\(index + 1).jpg")
                    try await client.page(job, to: page)
                    try self.onPage?(page, 300); received += 1
                    self.diagnostics.event("page_saved", ["received_files": received])
                }
            } catch { failure = error.localizedDescription; self.diagnostics.event("usb_scan_failed", error: error) }
            if let job = ownedJob {
                do { try await client.close(job) }
                catch { failure = (failure.map { $0 + " " } ?? "") + "Pages are preserved, but the scanner job did not close: \(error.localizedDescription)" }
            }
            self.busy = false
            if began { self.onEnd?(failure == nil && received > 0, failure) }
            if failure != nil || self.stopping { self.pause() }
            self.message = failure ?? (self.stopping ? "Scanner paused. Completed pages are saved." : "Page saved — add another sheet or Save PDF")
        }
    }
}

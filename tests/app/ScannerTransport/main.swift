import AppKit
import Foundation

final class FixtureDiscovery: ScannerDiscovery {
  var deliver: ((ScannerEndpoint) -> Void)?
  var fail: ((Error) -> Void)?
  var stops = 0
  func start(
    matching: @escaping (String) -> Bool,
    onEndpoint: @escaping (ScannerEndpoint) -> Void,
    onError: @escaping (Error) -> Void
  ) {
    precondition(matching("Brother DS-940DW [fixture]"))
    precondition(!matching("Unrelated scanner"))
    deliver = onEndpoint
    fail = onError
  }
  func stop() { stops += 1 }
}

final class FixtureScanner: URLProtocol {
  static var replies: [(Int, [String: String], Data)] = []
  static var requests: [URLRequest] = []
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.requests.append(request)
    precondition(!Self.replies.isEmpty, "Unexpected request")
    let (code, headers, bytes) = Self.replies.removeFirst()
    client?.urlProtocol(
      self,
      didReceive: HTTPURLResponse(
        url: request.url!, statusCode: code,
        httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: bytes)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

@main enum Tests {
  static let capabilities = Data(
    "<ScannerCapabilities><MakeAndModel>DS-940DW</MakeAndModel><AdfOption>Duplex</AdfOption><Adf><AdfSimplexInputCaps><MaxHeight>36600</MaxHeight></AdfSimplexInputCaps><AdfDuplexInputCaps><MaxHeight>4200</MaxHeight></AdfDuplexInputCaps></Adf></ScannerCapabilities>"
      .utf8)
  static func status(_ feeder: String) -> Data {
    Data("<ScannerStatus><State>Idle</State><AdfState>\(feeder)</AdfState></ScannerStatus>".utf8)
  }
  @MainActor static func waitUntil(_ done: () -> Bool) async throws {
    for _ in 0..<200 {
      if done() { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw PaperError("Timed out waiting for scanner state")
  }
  @MainActor static func main() async throws {
    let root = FileManager().temporaryDirectory.appendingPathComponent(
      "PaperIn-Transport-\(UUID())")
    defer { try? FileManager().removeItem(at: root) }

    // Opt-in read-only probe uses production Bonjour and URLSession, never starts a scan.
    if CommandLine.arguments.contains("--live-discovery") {
      let backend = ESCLScannerBackend(staging: root, profile: DS940Profile(), connection: .network)
      backend.connect()
      for _ in 0..<160 where !backend.connected && backend.listening {
        try await Task.sleep(nanoseconds: 100_000_000)
      }
      precondition(backend.connected, backend.message)
      precondition(backend.supportsDuplex)
      print("PASS live Wi-Fi Bonjour discovery, model verification and duplex capabilities")
      backend.pause()
      return
    }

    for xml in [
      "<ScannerCapabilities/>",
      "<ScannerCapabilities><MaxHeight>36600</MaxHeight></ScannerCapabilities>",
      "<ScannerCapabilities><Adf><AdfSimplexInputCaps><MaxHeight>4200</MaxHeight></AdfSimplexInputCaps><AdfDuplexInputCaps><MaxHeight>36600</MaxHeight></AdfDuplexInputCaps></Adf></ScannerCapabilities>",
    ] {
      let caps = DS940Profile().capabilities(from: try ScanXML.read(Data(xml.utf8)))
      precondition(caps.paperModes == [.standard])
    }
    let normal = try ScanXML.read(DS940Profile().settings(options: ScanOptions(duplex: true)))
    precondition(normal.values["Height"] == ["3508"] && normal.values["Duplex"] == ["true"])
    print(
      "PASS long-paper support requires the simplex limit; normal duplex retains its A4 request")

    let usb = try ScannerEndpoint.make(
      connection: .usb, host: "localhost.local.", port: 1234, resourcePath: nil)
    let wifi = try ScannerEndpoint.make(
      connection: .network, host: "scanner.local.", port: 8080, resourcePath: "scan/eSCL/")
    precondition(usb.base.absoluteString == "http://localhost:1234/eSCL")
    precondition(wifi.base.absoluteString == "http://scanner.local:8080/scan/eSCL")
    for (connection, host, port, path) in [
      (ScannerConnection.usb, "scanner.local", 80, "eSCL"),
      (.network, "example.com", 80, "eSCL"), (.network, "localhost.local", 80, "eSCL"),
      (.network, "scanner.local", 0, "eSCL"), (.network, "scanner.local", 65536, "eSCL"),
      (.network, "scanner.local", 80, "../eSCL"), (.network, "scanner.local", 80, "eSCL/%2e%2e"),
      (.network, "scanner.local", 80, "eSCL?target=remote"),
      (.network, "scanner.local", 80, "//remote/eSCL"),
    ] {
      do {
        _ = try ScannerEndpoint.make(
          connection: connection, host: host, port: port, resourcePath: path)
        fatalError("Unsafe endpoint accepted")
      } catch {}
    }
    print(
      "PASS discovery confines endpoints to USB loopback or Bonjour-local hosts and plain paths")

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FixtureScanner.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 60,
      bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let jpeg = bitmap.representation(using: .jpeg, properties: [:])!

    for connection in ScannerConnection.allCases {
      let discovery = FixtureDiscovery()
      let backend = ESCLScannerBackend(
        staging: root.appendingPathComponent(connection.rawValue),
        profile: DS940Profile(), connection: connection, discovery: discovery,
        makeClient: { ESCLClient(base: $0, session: session) })
      let endpoint = connection == .usb ? usb : wifi
      FixtureScanner.requests = []
      FixtureScanner.replies = [(200, [:], capabilities)]
      backend.connect()
      discovery.deliver?(endpoint)
      try await waitUntil { backend.connected }
      precondition(backend.supportsDuplex)
      var pages = 0
      var began = 0
      var outcome: Bool?
      backend.onCaptureBegan = { options in
        precondition(options.duplex)
        began += 1
      }
      backend.onImage = { image in
        let bytes = try Data(contentsOf: image.url)
        precondition(bytes == jpeg)
        pages += 1
      }
      backend.onCaptureEnded = { success, _ in outcome = success }
      let jobPath = endpoint.base.path + "/ScanJobs/owned"
      FixtureScanner.replies = [
        (200, [:], status("ScannerAdfLoaded")), (201, ["Location": jobPath], Data()),
        (200, [:], jpeg), (200, [:], jpeg), (204, [:], Data()),
      ]
      backend.scan(options: ScanOptions(duplex: true))
      backend.scan(options: ScanOptions(duplex: true))  // Double click cannot start a second job.
      try await waitUntil { !backend.busy }
      precondition(began == 1 && pages == 2 && outcome == true)
      precondition(
        FixtureScanner.requests.map { $0.httpMethod! } == [
          "GET", "GET", "POST", "GET", "GET", "DELETE",
        ])
      precondition(
        FixtureScanner.requests.allSatisfy {
          $0.url?.host == endpoint.base.host && $0.url?.port == endpoint.base.port
        })
      print(
        "PASS \(connection.title) shared duplex capture delivers both pages and closes one owned job"
      )

      pages = 0
      outcome = nil
      FixtureScanner.replies = [
        (200, [:], status("ScannerAdfLoaded")), (201, ["Location": jobPath], Data()),
        (200, [:], jpeg), (503, [:], Data()), (204, [:], Data()),
      ]
      backend.scan(options: ScanOptions(duplex: true))
      try await waitUntil { !backend.busy }
      precondition(pages == 1 && outcome == false && !backend.connected)
      precondition(FixtureScanner.requests.last?.httpMethod == "DELETE")
      print(
        "PASS \(connection.title) missing back preserves the front, closes the owned job and pauses"
      )

      for feeder in ["ScannerAdfEmpty", "ScannerAdfJam"] {
        FixtureScanner.replies = [(200, [:], capabilities)]
        backend.connect()
        discovery.deliver?(endpoint)
        try await waitUntil { backend.connected }
        let requestsBefore = FixtureScanner.requests.count
        FixtureScanner.replies = [(200, [:], status(feeder))]
        backend.scan(options: ScanOptions(duplex: true))
        try await waitUntil { !backend.busy }
        precondition(began == 2 && FixtureScanner.requests.count == requestsBefore + 1)
        precondition(!backend.connected)
        precondition(backend.message.contains(feeder == "ScannerAdfJam" ? "paper jam" : "No paper"))
        print("PASS \(connection.title) \(feeder) never begins a draft or creates a scan job")
      }

      FixtureScanner.replies = [(200, [:], capabilities)]
      backend.connect()
      discovery.deliver?(endpoint)
      try await waitUntil { backend.connected }
      let beforeLong = FixtureScanner.requests.count
      precondition(backend.snapshot.capabilities.paperModes.contains(.longPaper))
      backend.scan(options: ScanOptions(duplex: true, paperMode: .longPaper))
      precondition(!backend.busy && FixtureScanner.requests.count == beforeLong)
      precondition(backend.message.contains("one side"))
      pages = 0
      outcome = nil
      backend.onCaptureBegan = { options in
        precondition(!options.duplex && options.paperMode == .longPaper)
      }
      FixtureScanner.replies = [
        (200, [:], status("ScannerAdfLoaded")), (201, ["Location": jobPath], Data()),
        (200, [:], jpeg), (204, [:], Data()),
      ]
      backend.scan(options: ScanOptions(paperMode: .longPaper))
      try await waitUntil { !backend.busy }
      precondition(pages == 1 && outcome == true)
      let request = FixtureScanner.requests[beforeLong + 1]
      var body = request.httpBody ?? Data()
      if body.isEmpty, let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
          let count = stream.read(&buffer, maxLength: buffer.count)
          if count <= 0 { break }
          body.append(contentsOf: buffer.prefix(count))
        }
      }
      let settings = try ScanXML.read(body)
      precondition(settings.values["Height"] == ["21600"])
      precondition(settings.values["Duplex"] == ["false"])
      precondition(FixtureScanner.requests[beforeLong + 2].timeoutInterval == 180)
      backend.pause()
      print(
        "PASS \(connection.title) long-paper settings reach the job, receive one page, and reject duplex without a request"
      )

      FixtureScanner.replies = [
        (
          200, [:],
          Data(
            "<ScannerCapabilities><MakeAndModel>Other device</MakeAndModel></ScannerCapabilities>"
              .utf8)
        )
      ]
      backend.connect()
      discovery.deliver?(endpoint)
      try await waitUntil { !backend.listening }
      precondition(!backend.connected && backend.message.contains("did not identify"))
      let previousDelivery = discovery.deliver
      let previousError = discovery.fail
      backend.connect()
      previousDelivery?(endpoint)
      previousError?(PaperError("Stale callback"))
      precondition(backend.listening && !backend.connected)
      backend.pause()
      print(
        "PASS \(connection.title) rejects the wrong model and ignores callbacks from an earlier connection"
      )
    }
  }
}

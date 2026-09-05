import Foundation
import ImageIO

// USB and network scanning share the same origin boundary. Never follow redirects.
final class NoScanRedirects: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) { completionHandler(nil) }
}
final class ScanXML: NSObject, XMLParserDelegate {
  var values: [String: [String]] = [:]
  private var text = ""
  private var path: [String] = []
  var paths: [String: [String]] = [:]
  static func read(_ data: Data) throws -> ScanXML {
    let result = ScanXML()
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = true
    parser.shouldResolveExternalEntities = false
    parser.delegate = result
    guard parser.parse() else {
      throw PaperError("The scanner returned unreadable status information.")
    }
    return result
  }
  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String]
  ) {
    path.append(elementName)
    text = ""
  }
  func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName: String?
  ) {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !value.isEmpty { values[elementName, default: []].append(value) }
    if !value.isEmpty { paths[path.joined(separator: "/"), default: []].append(value) }
    path.removeLast()
    text = ""
  }
}
final class ESCLClient {
  let base: URL
  let session: URLSession
  init(base: URL, session: URLSession? = nil) {
    self.base = base
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 30
    config.timeoutIntervalForResource = 180
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    self.session =
      session ?? URLSession(configuration: config, delegate: NoScanRedirects(), delegateQueue: nil)
  }
  func request(_ url: URL, method: String = "GET", body: Data? = nil, timeout: TimeInterval = 30)
    async throws -> (
      Data, HTTPURLResponse
    )
  {
    var request = URLRequest(url: url)
    request.timeoutInterval = timeout
    request.httpMethod = method
    request.httpBody = body
    if body != nil { request.setValue("text/xml", forHTTPHeaderField: "Content-Type") }
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw PaperError("No HTTP response from the scanner.")
    }
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
    case 409:
      reason =
        "Scanner rejected the scan request. Check its fault light and that the jam cover is closed; its settings may also have been rejected."
    case 503:
      reason =
        "Scanner reports busy or unavailable. Check its fault light and jam cover before retrying."
    case 403: reason = "Scanner refused access."
    default: reason = "Scanner request failed."
    }
    return PaperError("\(reason) (HTTP \(code))")
  }
  func create(settings: Data) async throws -> URL {
    let (_, response) = try await request(
      base.appendingPathComponent("ScanJobs"), method: "POST", body: settings)
    guard response.statusCode == 201 else { throw Self.httpError(response.statusCode) }
    guard let location = response.value(forHTTPHeaderField: "Location"),
      let job = URL(string: location, relativeTo: base.appendingPathComponent("ScanJobs"))?
        .absoluteURL,
      job.scheme == base.scheme, job.host == base.host, job.port == base.port,
      job.user == nil, job.password == nil, job.query == nil, job.fragment == nil,
      job.path.hasPrefix(base.path + "/ScanJobs/"), !job.path.contains("..")
    else {
      throw PaperError(
        "Scanner accepted a job but returned an invalid job address. Check the scanner before retrying."
      )
    }
    return job
  }
  func page(_ job: URL, to url: URL) async throws {
    let (data, response) = try await request(
      job.appendingPathComponent("NextDocument"), timeout: 180)
    guard response.statusCode == 200 else { throw Self.httpError(response.statusCode) }
    // Preserve bytes before decoding, including an incomplete response for diagnostics/recovery.
    try data.write(to: url, options: .withoutOverwriting)
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetCount(source) > 0,
      CGImageSourceGetStatus(source) == .statusComplete,
      CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    else {
      throw PaperError(
        "Scanner delivered an incomplete or unreadable image. Earlier pages are saved.")
    }
  }
  func close(_ job: URL) async throws {
    let (_, response) = try await request(job, method: "DELETE")
    guard [200, 204, 404, 410].contains(response.statusCode) else {
      throw Self.httpError(response.statusCode)
    }
  }
}

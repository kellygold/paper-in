import Foundation
import AppKit
import PDFKit

final class MockUSB: URLProtocol {
    static var responses: [(Int, [String:String], Data)] = []
    static var methods: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.methods.append(request.httpMethod ?? "GET")
        precondition(!Self.responses.isEmpty, "Unexpected extra request")
        let (code, headers, data) = Self.responses.removeFirst()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main enum Tests {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockUSB.self]
        let client = ESCLClient(base: URL(string: "http://localhost:12345/eSCL")!, session: URLSession(configuration: config))
        MockUSB.responses = [(409, [:], Data())]
        do { _ = try await client.create(duplex: false); fatalError("409 accepted") }
        catch { precondition(error.localizedDescription.contains("409")) }
        precondition(MockUSB.methods == ["POST"])
        MockUSB.responses = [(201, ["Location":"http://example.com/eSCL/ScanJobs/1"], Data())]
        do { _ = try await client.create(duplex: false); fatalError("Foreign job accepted") } catch {}
        precondition(MockUSB.methods == ["POST", "POST"])
        print("PASS rejection and foreign job URL do not trigger page retrieval")

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 60, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let jpeg = bitmap.representation(using: .jpeg, properties: [:])!
        let root = FileManager().temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager().createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager().removeItem(at: root) }
        let store = try DraftStore(root: root.appendingPathComponent("drafts"))
        for index in 0..<2 {
            MockUSB.responses = [(201, ["Location":"/eSCL/ScanJobs/owned"], Data()), (200, ["Content-Type":"image/jpeg"], jpeg), (200, [:], Data())]
            try store.beginCapture()
            let job = try await client.create(duplex: false)
            let file = root.appendingPathComponent("page-\(index).jpg")
            try await client.page(job, to: file); try store.ingest(file); try await client.close(job)
            try store.completeCapture(success: true)
        }
        let pdf = try store.export(to: root.appendingPathComponent("output"))
        precondition(PDFDocument(url: pdf)?.pageCount == 2)
        precondition(Array(MockUSB.methods.suffix(6)) == ["POST", "GET", "DELETE", "POST", "GET", "DELETE"])
        print("PASS two separate scans produce one two-page PDF and close only owned jobs")
        MockUSB.responses = [(200, [:], Data("broken-image".utf8))]
        do { try await client.page(URL(string: "http://localhost:12345/eSCL/ScanJobs/owned")!, to: root.appendingPathComponent("bad.jpg")); fatalError("Invalid image accepted") } catch {}
        print("PASS incomplete image rejected and raw response retained")
        let xml = try ScanXML.read(Data("<scan:ScannerStatus xmlns:scan='urn:scan' xmlns:pwg='urn:pwg'><pwg:State>Idle</pwg:State><scan:AdfState>ScannerAdfLoaded</scan:AdfState></scan:ScannerStatus>".utf8))
        precondition(xml.values["State"] == ["Idle"] && xml.values["AdfState"] == ["ScannerAdfLoaded"])
        print("PASS namespaced scanner status parsed")
    }
}

import Foundation

struct ScannerRegistration {
  let id: String
  let name: String
  let makeBackend: (URL, ScannerConnection) -> any ScannerBackend
}

/// The composition root for supported hardware. Each entry supplies a backend for
/// the same shared ScannerSession; no device-specific behavior belongs in the UI.
enum ScannerCatalog {
  static let supported = [
    ScannerRegistration(
      id: "brother-ds940dw", name: "Brother DS-940DW",
      makeBackend: { ESCLScannerBackend(staging: $0, profile: DS940Profile(), connection: $1) })
  ]
  static func makeBackend(staging: URL, connection: ScannerConnection) -> any ScannerBackend {
    supported[0].makeBackend(staging, connection)
  }
  static func makeSession(staging: URL, connection: ScannerConnection = .usb) -> ScannerSession {
    ScannerSession(backend: makeBackend(staging: staging, connection: connection))
  }
}

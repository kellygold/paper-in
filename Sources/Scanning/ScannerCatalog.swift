import Foundation

struct ScannerRegistration {
  let id: String
  let name: String
  let makeBackend: (URL) -> any ScannerBackend
}

/// The composition root for supported hardware. Each entry supplies a backend for
/// the same shared ScannerSession; no device-specific behavior belongs in the UI.
enum ScannerCatalog {
  static let supported = [
    ScannerRegistration(
      id: "brother-ds940dw-usb", name: "Brother DS-940DW (USB)",
      makeBackend: { DS940USBBackend(staging: $0) })
  ]
  static func makeSession(staging: URL) -> ScannerSession {
    ScannerSession(backend: supported[0].makeBackend(staging))
  }
}

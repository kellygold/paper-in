import Foundation

protocol ESCLScannerProfile {
  var name: String { get }
  var resolutions: [Int] { get }
  func matchesService(_ name: String) -> Bool
  func matchesCapabilities(_ caps: ScanXML) -> Bool
  func capabilities(from caps: ScanXML) -> ScannerCapabilities
  func settings(options: ScanOptions) -> Data
}

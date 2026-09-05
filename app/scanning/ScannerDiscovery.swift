import Foundation
import dnssd

enum ScannerConnection: String, CaseIterable, Identifiable {
  case usb
  case network
  var id: String { rawValue }
  var title: String { self == .usb ? "USB" : "Wi-Fi" }
}

struct ScannerEndpoint {
  let base: URL

  /// Accept only a local USB proxy or a Bonjour-local scanner, with a plain path.
  static func make(connection: ScannerConnection, host: String, port: Int, resourcePath: String?)
    throws -> Self
  {
    guard (1...65535).contains(port) else { throw PaperError("Invalid scanner port.") }
    let normalized = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    let target: String
    if connection == .usb {
      guard ["localhost", "localhost.local"].contains(normalized) else {
        throw PaperError("USB scanner discovery returned a non-local address.")
      }
      target = "localhost"
    } else {
      guard normalized.hasSuffix(".local"), normalized != "localhost.local",
        normalized.utf8.allSatisfy({
          (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46
        })
      else {
        throw PaperError("Network scanner discovery returned an invalid local address.")
      }
      target = normalized
    }
    let raw = connection == .usb ? "eSCL" : (resourcePath ?? "eSCL")
    let path = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard !path.isEmpty, !raw.contains("//"),
      path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
        !$0.isEmpty && $0 != "." && $0 != ".."
      }),
      path.utf8.allSatisfy({
        (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
          || [45, 46, 47, 95].contains($0)
      })
    else {
      throw PaperError("Scanner discovery returned an invalid scan path.")
    }
    var parts = URLComponents()
    parts.scheme = "http"
    parts.host = target
    parts.port = port
    parts.path = "/" + path
    guard let url = parts.url else { throw PaperError("Invalid scanner address.") }
    return ScannerEndpoint(base: url)
  }
}

protocol ScannerDiscovery: AnyObject {
  func start(
    matching: @escaping (String) -> Bool,
    onEndpoint: @escaping (ScannerEndpoint) -> Void,
    onError: @escaping (Error) -> Void)
  func stop()
}

/// Only discovery differs between USB and Wi-Fi. Scan jobs use ESCLScannerBackend.
final class BonjourScannerDiscovery: ScannerDiscovery {
  private let connection: ScannerConnection
  private var browseRef: DNSServiceRef?
  private var resolveRef: DNSServiceRef?
  private var matching: ((String) -> Bool)?
  private var onEndpoint: ((ScannerEndpoint) -> Void)?
  private var onError: ((Error) -> Void)?
  init(connection: ScannerConnection) { self.connection = connection }
  deinit { stop() }

  func start(
    matching: @escaping (String) -> Bool,
    onEndpoint: @escaping (ScannerEndpoint) -> Void,
    onError: @escaping (Error) -> Void
  ) {
    stop()
    self.matching = matching
    self.onEndpoint = onEndpoint
    self.onError = onError
    let interface =
      connection == .usb ? kDNSServiceInterfaceIndexLocalOnly : UInt32(kDNSServiceInterfaceIndexAny)
    let type = connection == .usb ? "_ippusb._tcp" : "_uscan._tcp"
    let context = Unmanaged.passUnretained(self).toOpaque()
    let code = DNSServiceBrowse(
      &browseRef, 0, interface, type, "local.",
      { _, flags, interface, error, name, type, domain, context in
        guard let context else { return }
        let owner = Unmanaged<BonjourScannerDiscovery>.fromOpaque(context).takeUnretainedValue()
        guard error == 0 else {
          owner.fail(PaperError("Scanner discovery failed (\(error))."))
          return
        }
        guard flags & kDNSServiceFlagsAdd != 0, let name, let type, let domain,
          owner.resolveRef == nil, owner.matching?(String(cString: name)) == true
        else { return }
        let result = DNSServiceResolve(
          &owner.resolveRef, 0, interface, name, type, domain,
          { _, _, _, error, _, host, port, txtLength, txt, context in
            guard let context else { return }
            let owner = Unmanaged<BonjourScannerDiscovery>.fromOpaque(context).takeUnretainedValue()
            guard error == 0, let host else {
              owner.fail(PaperError("Scanner address could not be resolved (\(error))."))
              return
            }
            var resourcePath: String?
            if let txt {
              var length: UInt8 = 0
              if let value = TXTRecordGetValuePtr(txtLength, txt, "rs", &length) {
                resourcePath = String(data: Data(bytes: value, count: Int(length)), encoding: .utf8)
                guard resourcePath != nil else {
                  owner.fail(PaperError("Invalid scanner discovery text."))
                  return
                }
              }
            }
            do {
              let endpoint = try ScannerEndpoint.make(
                connection: owner.connection,
                host: String(cString: host), port: Int(UInt16(bigEndian: port)),
                resourcePath: resourcePath)
              owner.onEndpoint?(endpoint)
            } catch { owner.fail(error) }
          }, context)
        if result == 0, let ref = owner.resolveRef {
          let queued = DNSServiceSetDispatchQueue(ref, DispatchQueue.main)
          if queued != 0 {
            owner.fail(PaperError("Scanner resolution could not start (\(queued))."))
          }
        } else {
          owner.fail(PaperError("Scanner resolution failed (\(result))."))
        }
      }, context)
    if code == 0, let ref = browseRef {
      let queued = DNSServiceSetDispatchQueue(ref, DispatchQueue.main)
      if queued != 0 { fail(PaperError("Scanner discovery could not start (\(queued)).")) }
    } else {
      fail(PaperError("Scanner discovery failed (\(code))."))
    }
  }

  private func fail(_ error: Error) {
    // Defer cleanup until after the DNS callback has returned.
    let callback = onError
    DispatchQueue.main.async { callback?(error) }
  }
  func stop() {
    if let ref = browseRef {
      DNSServiceRefDeallocate(ref)
      browseRef = nil
    }
    if let ref = resolveRef {
      DNSServiceRefDeallocate(ref)
      resolveRef = nil
    }
    matching = nil
    onEndpoint = nil
    onError = nil
  }
}

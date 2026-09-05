import Foundation

// Local event timing and framework error codes only. No page images or extracted text.
final class Diagnostics {
  let url: URL
  private let started = Date()
  private let formatter = ISO8601DateFormatter()
  init(directory: URL) {
    url = directory.appendingPathComponent("connection-\(UUID().uuidString).jsonl")
    try? FileManager().createDirectory(at: directory, withIntermediateDirectories: true)
    FileManager().createFile(atPath: url.path, contents: nil)
    event(
      "app_started",
      [
        "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
          ?? "development", "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
      ])
  }
  func event(_ name: String, _ fields: [String: Any] = [:], error: Error? = nil) {
    var entry = fields
    entry["event"] = name
    entry["time"] = formatter.string(from: Date())
    entry["elapsed_ms"] = Int(Date().timeIntervalSince(started) * 1000)
    if let error {
      let ns = error as NSError
      entry["error_domain"] = ns.domain
      entry["error_code"] = ns.code
      entry["error_description"] = ns.localizedDescription
    }
    guard JSONSerialization.isValidJSONObject(entry),
      var data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
      let handle = try? FileHandle(forWritingTo: url)
    else { return }
    data.append(0x0a)
    do {
      try handle.seekToEnd()
      try handle.write(contentsOf: data)
      try handle.synchronize()
      try handle.close()
    } catch { try? handle.close() }
  }
}

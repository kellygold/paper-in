import Foundation

struct FilingSettings: Codable, Equatable {
  var enabled = false
  var autoFile = true
  var provider = "codex"
  var model = ""
  var rules =
    "Use Medical, Car, Home, Financial, Receipts and Personal where appropriate. Prefer existing folders. Keep related property and vehicle records together."
  var nodePath = ""
  var runtimePaths: [String: String] = [:]
}
struct ExportFilingIntent: Codable {
  var root: String
  var settings: FilingSettings
}
struct FilingRelation: Codable, Identifiable {
  var path: String
  var relationship: String
  var reason: String
  var id: String { path }
}
struct FilingProposal: Codable {
  var folder: String
  var filename: String
  var confidence: Double
  var reason: String
  var needsReview: Bool
  var related: [FilingRelation]
}
struct FilingJob: Codable, Identifiable {
  var id: String
  var created: String
  var state: String
  var original: String
  var root: String
  var proposal: FilingProposal?
  var error: String?
  var target: String?
  var displayName: String { proposal?.filename ?? URL(fileURLWithPath: original).lastPathComponent }
  var stateLabel: String {
    switch state {
    case "queued": return "Waiting to organize"
    case "analyzing": return "Reading and checking"
    case "review": return "Needs review"
    case "publishing": return "Finishing filing"
    case "filed": return "Filed"
    case "failed": return "Needs attention"
    case "undoing": return "Restoring"
    case "undone": return "Restored to inbox"
    default: return state
    }
  }
}

struct AIProviderDescriptor: Codable, Identifiable {
  var id: String
  var name: String
  var authentication: String
  var requiresModel: Bool
  var help: String
  var needsAPIKey: Bool { authentication == "apiKey" }
  static func bundled() throws -> [AIProviderDescriptor] {
    guard let file = Bundle.main.resourceURL?.appendingPathComponent("Worker/provider-catalog.json")
    else { throw PaperError("Provider catalog is missing.") }
    return try JSONDecoder().decode([AIProviderDescriptor].self, from: Data(contentsOf: file))
  }
}

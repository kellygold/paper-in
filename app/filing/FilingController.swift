import Combine
import Foundation

final class FilingController: ObservableObject {
  private(set) var providers: [AIProviderDescriptor] = []
  @Published var settings = FilingSettings()
  @Published var jobs: [FilingJob] = []
  @Published var busy = false
  @Published var error: String?
  let root: URL
  let demo: Bool
  private var timer: Timer?
  private var process: Process?
  private let fm = FileManager()
  private var rerun = false
  init(root: URL, demo: Bool) {
    self.root = root
    self.demo = demo
    do { providers = try AIProviderDescriptor.bundled() } catch {
      self.error = "Provider catalog could not be loaded. AI filing is unavailable."
    }
    let url = root.appendingPathComponent("filing-settings.json")
    if fm.fileExists(atPath: url.path) {
      do {
        settings = try JSONDecoder().decode(FilingSettings.self, from: Data(contentsOf: url))
      } catch {
        self.error = "AI settings could not be read. Filing is paused; saved PDFs are safe."
      }
    }
    refresh()
    if demo && CommandLine.arguments.contains("--demo-review") {
      jobs = [
        FilingJob(
          id: UUID().uuidString, created: "2026-08-14T12:00:00Z", state: "review",
          original: root.appendingPathComponent("Output/Example.pdf").path, root: root.path,
          proposal: FilingProposal(
            folder: "Car/Servicing", filename: "2026-08-14 - Example Auto - Service invoice.pdf",
            confidence: 0.88,
            reason:
              "This is a vehicle service invoice. The document date and issuer support this name. Confirm the new folder before filing.",
            needsReview: true,
            related: [
              FilingRelation(
                path: "Car/Servicing/Previous service.pdf", relationship: "related",
                reason: "Another service record for the same vehicle.")
            ]), error: nil, target: nil)
      ]
    }
    timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      self?.refresh()
    }
    if settings.enabled && !demo { DispatchQueue.main.async { self.run() } }
  }
  deinit { timer?.invalidate() }
  func persist(_ next: FilingSettings) throws {
    if next.enabled {
      _ = try nodeExecutable(next)
      guard let descriptor = providers.first(where: { $0.id == next.provider }) else {
        throw PaperError("Choose an available AI provider.")
      }
      if descriptor.requiresModel && next.model.trimmingCharacters(in: .whitespaces).isEmpty {
        throw PaperError("Enter the API model to use.")
      }
    }
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    try JSONEncoder().encode(next).write(
      to: root.appendingPathComponent("filing-settings.json"), options: .atomic)
    settings = next
    if next.enabled && !demo { run() }
  }
  private var refreshing = false
  private var refreshAgain = false
  private let refreshQueue = DispatchQueue(label: "paper.filing.list", qos: .utility)
  func refresh() {
    guard !demo else { return }
    if refreshing {
      refreshAgain = true
      return
    }
    refreshing = true
    let folder = root.appendingPathComponent("filing/jobs")
    refreshQueue.async { [weak self] in
      let fm = FileManager()
      var next: [FilingJob] = []
      var issue: String?
      do {
        if fm.fileExists(atPath: folder.path) {
          for dir in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
          where UUID(uuidString: dir.lastPathComponent) != nil {
            let file = dir.appendingPathComponent("job.json")
            guard fm.fileExists(atPath: file.path) else { continue }
            do {
              var job = try JSONDecoder().decode(FilingJob.self, from: Data(contentsOf: file))
              let location = job.state == "filed" ? (job.target ?? job.original) : job.original
              job.fileMissing = !fm.fileExists(atPath: location)
              next.append(job)
            } catch {
              issue = "A filing record could not be read. Other documents remain available."
            }
          }
        }
      } catch { issue = "The filing list could not be read. Originals are preserved." }
      let result = next.sorted { $0.created > $1.created }
      DispatchQueue.main.async {
        guard let self else { return }
        self.refreshing = false
        if self.jobs != result { self.jobs = result }
        if let issue { self.error = issue }
        if self.refreshAgain {
          self.refreshAgain = false
          self.refresh()
        }
      }
    }
  }
  func nodeExecutable(_ configuration: FilingSettings) throws -> URL {
    let home = fm.homeDirectoryForCurrentUser.path
    // DMG builds include Node; explicit overrides still take precedence.
    let bundled = Bundle.main.resourceURL?.appendingPathComponent("Runtime/bin/node").path ?? ""
    var paths = [configuration.nodePath, bundled, "/opt/homebrew/bin/node", "/usr/local/bin/node"]
    paths += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map {
      String($0) + "/node"
    }
    let nvm = URL(fileURLWithPath: home + "/.nvm/versions/node")
    if let versions = try? fm.contentsOfDirectory(at: nvm, includingPropertiesForKeys: nil) {
      paths += versions.sorted {
        $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending
      }.map { $0.appendingPathComponent("bin/node").path }
    }
    guard let path = paths.first(where: { !$0.isEmpty && fm.isExecutableFile(atPath: $0) }) else {
      throw PaperError(
        "AI filing needs Node.js 22 or later. Install it or choose its executable in AI settings.")
    }
    return URL(fileURLWithPath: path)
  }
  func stop() { if let process, process.isRunning { process.terminate() } }
  func run() {
    guard settings.enabled && !demo else { return }
    perform("run")
  }
  func perform(_ command: String, id: String? = nil, folder: String? = nil, filename: String? = nil)
  {
    guard !demo else {
      error = "Demo mode does not contact AI providers."
      return
    }
    guard !busy else {
      if command == "run" { rerun = true }
      return
    }
    do {
      let node = try nodeExecutable(settings)
      guard let resources = Bundle.main.resourceURL else {
        throw PaperError("App resources are missing.")
      }
      let worker = resources.appendingPathComponent("Worker/main.mjs")
      let helper = resources.appendingPathComponent("PaperOCR")
      guard fm.fileExists(atPath: worker.path), fm.isExecutableFile(atPath: helper.path) else {
        throw PaperError("AI worker is missing. Rebuild or reinstall Paper In.")
      }
      var request: [String: Any] = ["root": root.path, "helper": helper.path, "command": command]
      if let id { request["id"] = id }
      if command == "retry" {
        request["settings"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings))
      }
      if let folder, let filename {
        request["override"] = ["folder": folder, "filename": filename]
      }
      var secrets: [String: String] = [:]
      // Keys travel only through stdin to this child, never arguments or queue manifests.
      for provider in providers where command == "run" && provider.needsAPIKey {
        if let key = try KeychainStore.read(provider.id) { secrets[provider.id] = key }
      }
      request["secrets"] = secrets
      let input = try JSONSerialization.data(withJSONObject: request)
      busy = true
      error = nil
      let task = Process()
      task.executableURL = node
      task.arguments = [worker.path]
      var environment = ProcessInfo.processInfo.environment
      for key in Array(environment.keys)
      where key.contains("API_KEY") || key.contains("TOKEN") || key.hasPrefix("ANTHROPIC_")
        || key.hasPrefix("OPENAI_")
      { environment.removeValue(forKey: key) }
      let home = fm.homeDirectoryForCurrentUser.path
      environment["PATH"] = [
        node.deletingLastPathComponent().path, home + "/.local/bin", "/opt/homebrew/bin",
        "/usr/local/bin", "/usr/bin", "/bin",
      ].joined(separator: ":")
      task.environment = environment
      let stdin = Pipe()
      let stdout = Pipe()
      let stderr = Pipe()
      task.standardInput = stdin
      task.standardOutput = stdout
      task.standardError = stderr
      process = task
      DispatchQueue.global(qos: .utility).async {
        var failure: String?
        var completed = false
        do {
          try task.run()
          DispatchQueue.global(qos: .utility).async {
            _ = stderr.fileHandleForReading.readDataToEndOfFile()
          }
          try stdin.fileHandleForWriting.write(contentsOf: input)
          try stdin.fileHandleForWriting.close()
          let output = stdout.fileHandleForReading.readDataToEndOfFile()
          task.waitUntilExit()
          if let result = try JSONSerialization.jsonObject(with: output) as? [String: Any] {
            completed = result["ok"] as? Bool == true && task.terminationStatus == 0
            failure =
              completed
              ? result["warning"] as? String
              : result["error"] as? String ?? "Filing failed."
          } else if task.terminationStatus != 0 {
            failure = "AI worker stopped. The PDF is safe; retry when ready."
          }
        } catch {
          failure =
            "AI worker could not finish. Check Node.js and provider setup. Your PDFs are safe."
        }
        DispatchQueue.main.async {
          self.busy = false
          self.process = nil
          self.error = failure
          self.refresh()
          let again = self.rerun || command == "retry"
          self.rerun = false
          if again && completed { self.run() }
        }
      }
    } catch { self.error = error.localizedDescription }
  }
}

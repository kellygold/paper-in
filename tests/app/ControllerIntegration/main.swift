import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
let marker = try String(
  contentsOf: root.appendingPathComponent(".synthetic-fixture"), encoding: .utf8)
precondition(
  marker == "Paper In synthetic integration fixture", "Synthetic test directory required")
let account = "synthetic-keychain-test-" + UUID().uuidString
try KeychainStore.save("synthetic-test-value", account: account)
let stored = try KeychainStore.read(account)
precondition(stored == "synthetic-test-value")
try KeychainStore.save("", account: account)
let removed = try KeychainStore.read(account)
precondition(removed == nil)
print("PASS Keychain key store/read/remove")
let filing = FilingController(root: root, demo: false)
var settings = FilingSettings()
settings.enabled = true
settings.provider = "codex"
if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Runtime/bin/node"),
  FileManager().isExecutableFile(atPath: bundled.path)
{
  let resolved = try filing.nodeExecutable(settings)
  precondition(
    resolved.standardizedFileURL.path == bundled.standardizedFileURL.path,
    "Bundled Node must be the default: \(resolved.path) vs \(bundled.path)")
  var overridden = settings
  overridden.nodePath = "/usr/bin/true"
  let explicit = try filing.nodeExecutable(overridden)
  precondition(
    explicit.path == overridden.nodePath,
    "Explicit executable override must take precedence")
  print("PASS bundled Node selection and explicit override")
}
try filing.persist(settings)
func settle() {
  let deadline = Date().addingTimeInterval(300)
  repeat {
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    filing.refresh()
  } while filing.busy && Date() < deadline
  precondition(!filing.busy, "Worker timeout")
  precondition(filing.error == nil, filing.error ?? "")
}
settle()
precondition(filing.jobs.count == 1)
var job = filing.jobs[0]
precondition(["filed", "review"].contains(job.state), job.error ?? job.state)
if job.state == "review" {
  filing.perform("apply", id: job.id)
  settle()
}
job = filing.jobs[0]
precondition(job.state == "filed")
filing.perform("undo", id: job.id)
settle()
precondition(filing.jobs[0].state == "undone")
print("PASS native controller -> bundled worker -> local OCR -> live Codex -> filing -> Undo")

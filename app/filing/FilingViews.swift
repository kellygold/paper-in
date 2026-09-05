import AppKit
import SwiftUI

struct FilingSettingsView: View {
  @ObservedObject var filing: FilingController
  @Environment(\.dismiss) private var dismiss
  @State private var configuration = FilingSettings()
  @State private var key = ""
  @State private var message: String?
  var provider: AIProviderDescriptor? { filing.providers.first { $0.id == configuration.provider } }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Organize after saving").font(.title2.bold())
      Text(
        "Your PDF is saved first. AI can then name it, find its folder and check related documents while you keep scanning."
      ).foregroundStyle(.secondary)
      Toggle("Enable AI filing for new scans", isOn: $configuration.enabled)
      Picker(
        "Provider",
        selection: Binding(
          get: { configuration.provider },
          set: { next in
            guard next != configuration.provider else { return }
            configuration.provider = next
            configuration.model = ""
            key = ""
          })
      ) {
        ForEach(filing.providers) { provider in Text(provider.name).tag(provider.id) }
      }
      TextField(
        provider?.requiresModel == true
          ? "API model (required)" : "Model (blank uses provider default)",
        text: $configuration.model)
      if provider?.needsAPIKey == true {
        SecureField("New API key (leave blank to keep saved key)", text: $key)
        HStack {
          Button("Store key in Keychain") {
            do {
              guard !key.isEmpty else { return }
              try KeychainStore.save(key, account: configuration.provider)
              key = ""
              message = "Key stored in Keychain."
            } catch { message = error.localizedDescription }
          }
          Button("Remove saved key") {
            do {
              try KeychainStore.save("", account: configuration.provider)
              message = "Saved key removed."
            } catch { message = error.localizedDescription }
          }
        }.font(.caption)
      } else {
        Text(provider?.help ?? "Choose a provider.").font(.caption).foregroundStyle(.secondary)
      }
      Toggle("Automatically file clear matches", isOn: $configuration.autoFile)
      Text(
        "Uncertain matches, new folders, duplicates and possible continuation pages always need review. Originals are retained; filed documents can be undone."
      ).font(.caption).foregroundStyle(.secondary)
      Text("Filing preferences").font(.headline)
      TextEditor(text: $configuration.rules).frame(height: 75).border(Color.gray.opacity(0.2))
      DisclosureGroup("Runtime paths") {
        TextField("Node.js executable (auto-detect)", text: $configuration.nodePath)
        ForEach(filing.providers.filter { $0.authentication == "runtime" }) { provider in
          TextField(
            "\(provider.name) executable (SDK default)",
            text: Binding(
              get: { configuration.runtimePaths[provider.id] ?? "" },
              set: { configuration.runtimePaths[provider.id] = $0 }))
        }
      }
      Text(
        "When enabled, extracted document text, folder names and excerpts from up to eight related PDFs are sent to your selected provider. Scanning itself stays local. API usage is billed separately; provider runtimes may retain their own session data."
      ).font(.caption).foregroundStyle(.secondary)
      if let message { Text(message).font(.caption).foregroundStyle(.orange) }
      HStack {
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("Save settings") {
          do {
            if !key.isEmpty {
              try KeychainStore.save(key, account: configuration.provider)
              key = ""
            }
            try filing.persist(configuration)
            dismiss()
          } catch { message = error.localizedDescription }
        }.keyboardShortcut(.defaultAction)
      }
    }.textFieldStyle(.roundedBorder).padding(24).frame(width: 570).background(
      Color(red: 0.98, green: 0.975, blue: 0.96)
    )
    .onAppear { configuration = filing.settings }
  }
}
struct FilingReviewView: View {
  @ObservedObject var filing: FilingController
  @Environment(\.dismiss) private var dismiss
  @State private var selected: String?
  @State private var folder = ""
  @State private var filename = ""
  var selectedJob: FilingJob? { filing.jobs.first { $0.id == selected } }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Saved documents").font(.title2.bold())
        Spacer()
        if filing.busy {
          ProgressView().controlSize(.small)
          Text("Organizing…").font(.caption)
        }
        Button("Done") { dismiss() }
      }
      HStack(alignment: .top, spacing: 20) {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(filing.jobs) { job in
              Button {
                choose(job)
              } label: {
                VStack(alignment: .leading, spacing: 5) {
                  Text(job.displayName).lineLimit(2).font(.system(size: 12, weight: .medium))
                  Text(job.stateLabel).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                  .background(
                    selected == job.id ? Color.green.opacity(0.10) : Color.gray.opacity(0.05)
                  ).clipShape(RoundedRectangle(cornerRadius: 6))
              }.buttonStyle(.plain)
            }
          }
        }.frame(width: 250)
        if let job = selectedJob {
          VStack(alignment: .leading, spacing: 12) {
            Text(job.stateLabel).font(.headline)
            if let proposal = job.proposal {
              Text(proposal.reason).font(.callout).textSelection(.enabled)
              TextField("Folder relative to your scan folder", text: $folder)
              TextField("Filename.pdf", text: $filename)
              ForEach(proposal.related) { relation in
                VStack(alignment: .leading, spacing: 3) {
                  Text("\(relation.relationship.capitalized): \(relation.path)").font(
                    .caption.bold())
                  Text(relation.reason).font(.caption)
                }
              }
              if job.state == "review" {
                Button("File with this name and folder") {
                  filing.perform("apply", id: job.id, folder: folder, filename: filename)
                }.disabled(filing.busy)
              }
            }
            if let error = job.error { Text(error).foregroundStyle(.orange).font(.callout) }
            if job.state == "filed" {
              Button("Undo filing") { filing.perform("undo", id: job.id) }.disabled(filing.busy)
            }
            if ["failed", "undone", "publishing", "undoing"].contains(job.state) {
              Button(
                ["publishing", "undoing"].contains(job.state) ? "Retry filing" : "Retry analysis"
              ) {
                filing.perform("retry", id: job.id)
              }.disabled(filing.busy)
            }
            if job.state == "filed" && job.error != nil {
              Button("Retry inbox cleanup") { filing.perform("apply", id: job.id) }
                .disabled(filing.busy)
            }
            Button("Show PDF in Finder") {
              let path = job.state == "filed" ? (job.target ?? job.original) : job.original
              NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            Text(
              "All originals are kept in Paper In’s application data. Filing never merges or deletes a related document."
            ).font(.caption).foregroundStyle(.secondary)
            Spacer()
          }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
          Text(
            filing.jobs.isEmpty
              ? "Save a document with AI filing enabled to see it here."
              : "Select a document to review its location."
          ).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }
      }.frame(height: 400)
      if let error = filing.error { Text(error).font(.caption).foregroundStyle(.orange) }
      HStack {
        Button("Resume queue") { filing.run() }.disabled(filing.busy || !filing.settings.enabled)
        Spacer()
        Text("\(filing.jobs.count) saved documents").font(.caption).foregroundStyle(.secondary)
      }
    }.padding(24).frame(width: 850).background(Color(red: 0.98, green: 0.975, blue: 0.96))
      .textFieldStyle(.roundedBorder)
      .onAppear { if let first = filing.jobs.first { choose(first) } }
  }
  func choose(_ job: FilingJob) {
    selected = job.id
    folder = job.proposal?.folder ?? ""
    filename = job.proposal?.filename ?? ""
  }
}
struct FilingToolbar: View {
  @ObservedObject var filing: FilingController
  @State private var settingsOpen = false
  @State private var reviewOpen = false
  var body: some View {
    HStack(spacing: 12) {
      Button(filing.settings.enabled ? "AI filing on" : "AI filing…") { settingsOpen = true }
      Button(
        "Saved documents\(filing.jobs.filter { ["review","failed"].contains($0.state) }.isEmpty ? "" : " · needs review")"
      ) { reviewOpen = true }
      if filing.busy {
        ProgressView().controlSize(.mini)
        Text("Organizing in background").font(.caption)
      }
      if let error = filing.error {
        Text(error).font(.caption).foregroundStyle(.orange).lineLimit(2)
      }
      Spacer()
    }.font(.caption)
      .onAppear {
        if filing.demo && CommandLine.arguments.contains("--demo-settings") { settingsOpen = true }
        if filing.demo && CommandLine.arguments.contains("--demo-review") { reviewOpen = true }
      }
      .sheet(isPresented: $settingsOpen) { FilingSettingsView(filing: filing) }
      .sheet(isPresented: $reviewOpen) { FilingReviewView(filing: filing) }
  }
}

import SwiftUI

/// Capture choices, cleanup preferences and saving share one compact control area.
struct ScanControls: View {
  @ObservedObject var model: AppModel
  @ObservedObject var scanner: ScannerSession
  @State private var showingOptions = false
  private let green = Color(red: 0.12, green: 0.36, blue: 0.31)

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let failure = model.failure {
        Label(failure, systemImage: "exclamationmark.triangle")
          .foregroundStyle(Color(red: 0.65, green: 0.20, blue: 0.12)).textSelection(.enabled)
      }
      if let notice = model.notice, !model.demo {
        Text(notice).foregroundStyle(.secondary).textSelection(.enabled)
      }
      HStack(alignment: .center, spacing: 12) {
        Picker("Paper", selection: Binding(get: { model.paperMode }, set: model.choosePaperMode)) {
          ForEach(model.availablePaperModes) { mode in Text(mode.title).tag(mode) }
        }.frame(width: 170)
          .disabled(!model.canEdit || (!model.demo && !scanner.connected))
        Picker("Sides", selection: Binding(get: { model.duplex }, set: model.chooseSides)) {
          Text("One").tag(false)
          Text("Both").tag(true).disabled(!model.canScanBothSides)
        }.pickerStyle(.segmented).frame(width: 165).disabled(!model.canEdit)
          .help(
            model.canScanBothSides
              ? "Scan one side or both sides of each sheet."
              : "This paper mode supports one side at a time."
          )
          .onChange(of: model.duplex) { _, value in
            if !model.demo { UserDefaults().set(value, forKey: "bothSides") }
          }
        Button {
          showingOptions.toggle()
        } label: {
          Label("Options", systemImage: "slider.horizontal.3")
        }.popover(isPresented: $showingOptions) { options }
        Spacer(minLength: 8)
        if scanner.busy { Button("Stop") { scanner.pause() } }
        Button {
          model.scan()
        } label: {
          Label(model.pages.isEmpty ? "Scan" : "Add sheet", systemImage: "plus")
            .padding(.horizontal, 8).padding(.vertical, 7)
        }.keyboardShortcut(.space, modifiers: [])
          .disabled(!model.canEdit || (!model.demo && !scanner.connected))
        Button {
          model.save()
        } label: {
          Text(model.exporting ? "Saving…" : "Save PDF").fontWeight(.semibold)
            .padding(.horizontal, 14).padding(.vertical, 7)
        }.buttonStyle(.borderedProminent).tint(green).keyboardShortcut("s", modifiers: .command)
          .disabled(scanner.busy || model.exporting || model.pages.isEmpty || model.store == nil)
      }
      HStack {
        Text(model.demo ? "Preview mode" : scanner.message).textSelection(.enabled)
        Spacer()
        if model.skippedPageCount > 0 {
          Text(
            "\(model.skippedPageCount) blank \(model.skippedPageCount == 1 ? "page" : "pages") skipped"
          )
        }
      }.font(.caption).foregroundStyle(.secondary)
      if model.paperMode == .automatic {
        Text("Auto paper edges · Up to 35.6 cm. For longer paper, choose Long receipt.")
          .font(.caption).foregroundStyle(.secondary)
      } else if model.paperMode == .longPaper {
        Text(
          "Up to 1.8 m · This scanner supports long receipts on one side at a time. Close the output guide for straight-through feeding."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Divider()
      HStack(spacing: 12) {
        FilingToolbar(filing: model.filing)
        Spacer()
        Image(systemName: "folder").foregroundStyle(.secondary)
        Button {
          model.chooseFolder()
        } label: {
          Text(
            model.destination.path.replacingOccurrences(
              of: FileManager().homeDirectoryForCurrentUser.path, with: "~")
          )
          .lineLimit(1).truncationMode(.middle)
        }.buttonStyle(.link).disabled(!model.canEdit).help("Change the folder for saved PDFs")
        if !model.pages.isEmpty {
          Text("\(model.pages.count) in draft").foregroundStyle(green)
        }
      }.font(.caption)
    }.padding(20)
  }

  private var options: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Scan options").font(.headline)
      Text("300 dpi · Colour").font(.caption).foregroundStyle(.secondary)
      Toggle("Skip blank pages", isOn: $model.skipBlanks).disabled(!model.canEdit)
        .onChange(of: model.skipBlanks) { _, value in
          if !model.demo { UserDefaults().set(value, forKey: "skipBlanks") }
        }
      Text(
        "Applies to either side and single-sided scans. Originals remain available to restore before saving."
      )
      .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      Toggle("Trim scanner borders", isOn: $model.autoCrop).disabled(!model.canEdit)
        .onChange(of: model.autoCrop) { _, value in
          if !model.demo { UserDefaults().set(value, forKey: "autoCrop") }
        }
      Text(
        "Cleans up image edges after scanning. Choose A4 instead of Auto if you need the full capture area."
      )
      .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      Divider()
      Picker("Connection", selection: $model.connection) {
        ForEach(ScannerConnection.allCases) { connection in Text(connection.title).tag(connection) }
      }.pickerStyle(.segmented).disabled(scanner.busy || model.exporting)
        .onChange(of: model.connection) { _, value in model.changeConnection(value) }
      if model.connection == .network {
        Text("Connect the scanner and Mac to the same local network.").font(.caption)
          .foregroundStyle(.secondary)
      }
    }.padding(20).frame(width: 310)
  }
}

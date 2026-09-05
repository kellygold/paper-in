import AppKit
import PDFKit
import SwiftUI

struct ContentView: View {
  @ObservedObject var model: AppModel
  @ObservedObject var scanner: ScannerSession
  private let green = Color(red: 0.12, green: 0.36, blue: 0.31)
  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center) {
        Image(systemName: "doc.viewfinder").font(.system(size: 28, weight: .medium))
          .foregroundStyle(green)
        VStack(alignment: .leading, spacing: 3) {
          Text("Paper In").font(.system(size: 23, weight: .semibold))
          Text("One document, as many pages as you need.").font(.system(size: 12)).foregroundStyle(
            .secondary)
        }
        Spacer()
        Circle().fill(scanner.connected ? green : Color.secondary.opacity(0.5)).frame(
          width: 7, height: 7)
        Text(model.demo ? "Preview" : scanner.scannerName).font(.system(size: 12))
        if !model.demo {
          Button(scanner.listening ? "Pause scanner" : "Connect") {
            if scanner.listening { scanner.pause() } else { scanner.connect() }
          }.disabled(scanner.busy || model.store == nil)
          if scanner.listening && !scanner.connected {
            Button("Retry") { scanner.retry() }.disabled(scanner.busy)
          }
        }
      }.padding(24)
      Divider()
      HStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Text("YOUR DOCUMENT").font(.system(size: 10, weight: .semibold)).tracking(1.4)
              .foregroundStyle(.secondary)
            Spacer()
            Text("\(model.pages.count)").monospacedDigit().font(.system(size: 12, weight: .medium))
          }
          if model.pages.isEmpty {
            Text(
              model.skippedPageCount > 0
                ? "Blank pages were skipped. You can restore them below."
                : "Your pages will appear here."
            ).font(.callout).foregroundStyle(.secondary).padding(
              .top, 10)
          }
          ScrollView {
            LazyVStack(spacing: 9) {
              if model.pairedPreview {
                ForEach(Array(model.sheets.enumerated()), id: \.element.id) { index, sheet in
                  Button {
                    model.select(sheet.visible.first?.id)
                  } label: {
                    HStack(spacing: 8) {
                      ForEach(sheet.visible.prefix(2)) { page in
                        PageThumbnail(store: model.store, page: page).id(
                          page.id + String(page.rotation) + String(describing: page.crop))
                      }
                      VStack(alignment: .leading, spacing: 3) {
                        Text(
                          sheet.pages.first?.sheetID == nil
                            ? "Page \(index + 1)" : "Sheet \(index + 1)"
                        ).font(.system(size: 13, weight: .medium))
                        Text(
                          sheet.pages.contains(where: { $0.blankSkipped == true })
                            ? "Blank page skipped" : (sheet.paired ? "Front + back" : "One side")
                        ).font(.system(size: 10))
                          .foregroundStyle(.secondary)
                      }
                      Spacer()
                    }.padding(10).background(
                      model.selectedSheet?.id == sheet.id ? green.opacity(0.09) : Color.white
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                  }.buttonStyle(.plain)
                }
              } else {
                ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                  Button {
                    model.select(page.id)
                  } label: {
                    HStack(spacing: 10) {
                      PageThumbnail(store: model.store, page: page).id(
                        page.id + String(page.rotation) + String(describing: page.crop))
                      VStack(alignment: .leading, spacing: 3) {
                        Text("Page \(index + 1)").font(.system(size: 13, weight: .medium))
                        if page.expectedSides == 2 {
                          Text(page.side == 1 ? "Back" : "Front").font(.caption).foregroundStyle(
                            .secondary)
                        }
                      }
                      Spacer()
                    }.padding(10).background(
                      model.selected == page.id ? green.opacity(0.09) : Color.white
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                  }.buttonStyle(.plain)
                }
              }
            }
          }
          if model.hasRemovedPages {
            Button("Restore page") { model.edit { try $0.restoreLastRemoved() } }.font(
              .caption
            ).disabled(!model.canEdit)
          }
          Text("Completed pages stay here until you save your PDF.").font(.system(size: 11))
            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(20).frame(width: 225)
        Divider()
        VStack(spacing: 0) {
          if model.pages.isEmpty {
            VStack(spacing: 15) {
              Image(systemName: "scanner").font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(green)
              Text(
                model.skippedPageCount > 0 ? "Blank pages skipped" : "Start with a sheet of paper"
              ).font(.system(size: 23, weight: .medium))
              Text(
                model.skippedPageCount > 0
                  ? "Add another sheet, or restore a skipped page from the sidebar."
                  : "Scan each sheet, then save them together as one PDF."
              ).foregroundStyle(
                .secondary)
              if let last = model.lastExport, model.skippedPageCount == 0 {
                Button("Show saved PDF") { NSWorkspace.shared.activateFileViewerSelecting([last]) }
              }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white)
          } else {
            HStack {
              Button {
                model.navigatePage(by: -1)
              } label: {
                Image(systemName: "chevron.left")
              }.help("Previous page")
                .accessibilityLabel("Previous page")
                .disabled((model.selectedPageIndex ?? 0) == 0)
              Text("Page \((model.selectedPageIndex ?? 0) + 1) of \(model.pages.count)")
                .font(.caption).foregroundStyle(.secondary)
              Button {
                model.navigatePage(by: 1)
              } label: {
                Image(systemName: "chevron.right")
              }.help("Next page")
                .accessibilityLabel("Next page")
                .disabled((model.selectedPageIndex ?? 0) >= model.pages.count - 1)
              Spacer()
              Picker("Layout", selection: $model.pairedPreview) {
                Text("Front + back").tag(true)
                Text("Single page").tag(false)
              }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
            }.padding(10).background(Color.white)
            SheetPreview(model: model)
            HStack(spacing: 16) {
              Text(
                "Page \((model.pages.firstIndex { $0.id == model.selected } ?? 0) + 1) of \(model.pages.count)"
              ).font(.caption).foregroundStyle(.secondary)
              Spacer()
              Button {
                model.moveSelectedPage(by: -1)
              } label: {
                Label("Move earlier", systemImage: "arrow.up")
              }.disabled((model.selectedPageIndex ?? 0) == 0)
              Button {
                model.moveSelectedPage(by: 1)
              } label: {
                Label("Move later", systemImage: "arrow.down")
              }.disabled((model.selectedPageIndex ?? 0) >= model.pages.count - 1)
              Button {
                if let id = model.selected, let page = model.pages.first(where: { $0.id == id }) {
                  model.edit { try $0.setAutoCrop(id, enabled: page.crop == nil) }
                }
              } label: {
                Label(
                  model.pages.first(where: { $0.id == model.selected })?.crop == nil
                    ? "Auto crop" : "Full scan", systemImage: "crop")
              }
              Button {
                if let id = model.selected { model.edit { try $0.rotate(id) } }
              } label: {
                Label("Rotate", systemImage: "rotate.right")
              }
              Button {
                if let id = model.selected { model.edit { try $0.remove(id) } }
              } label: {
                Label("Remove", systemImage: "minus.circle")
              }
            }.buttonStyle(.borderless).disabled(!model.canEdit).padding(15).background(Color.white)
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      Divider()
      ScanControls(model: model, scanner: scanner)
    }
    .frame(minWidth: 900, minHeight: 660)
    .background(Color(red: 0.98, green: 0.975, blue: 0.96))
    .onChange(of: scanner.paperModes) { _, _ in
      model.reconcilePaperModes()
    }
    .onChange(of: scanner.connected) { _, _ in model.reconcilePaperModes() }
    .onAppear { renderIfRequested() }
  }
  private func renderIfRequested() {
    guard let index = CommandLine.arguments.firstIndex(of: "--screenshot"),
      CommandLine.arguments.indices.contains(index + 1)
    else { return }
    let output = CommandLine.arguments[index + 1]
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
      guard
        let window = NSApplication.shared.windows.first(where: {
          $0.contentView != nil && $0.frame.width > 500
        }),
        let view = (window.attachedSheet ?? window).contentView,
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
      else { return }
      view.cacheDisplay(in: view.bounds, to: bitmap)
      try? bitmap.representation(using: .png, properties: [:])?.write(
        to: URL(fileURLWithPath: output))
      if let sheet = window.attachedSheet {
        window.endSheet(sheet)
        sheet.orderOut(nil)
      }
      NSApplication.shared.terminate(nil)
    }
  }
}

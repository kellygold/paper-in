import AppKit
import PDFKit
import SwiftUI

struct PageThumbnail: View {
  let folder: URL?
  let page: StoredPage
  @State private var thumbnail: NSImage?
  var body: some View {
    Group {
      if let thumbnail {
        Image(nsImage: thumbnail).resizable().scaledToFit()
      } else {
        Image(systemName: "doc.text").foregroundStyle(.secondary)
      }
    }.frame(width: 33, height: 44)
      .task(id: folder.map { PreviewRenderer.key(folder: $0, page: page, pixels: 140) }) {
        guard let folder else { return }
        let rendered = try? await PreviewRenderer.shared.image(
          folder: folder, page: page, pixels: 140)
        if !Task.isCancelled, let rendered {
          thumbnail = NSImage(cgImage: rendered.image, size: .zero)
        }
      }
  }
}

struct PagePreview: View {
  let image: NSImage?
  var loading = false
  @State private var zoom: CGFloat = 1
  var body: some View {
    VStack(spacing: 0) {
      GeometryReader { geometry in
        if let image {
          ScrollView([.horizontal, .vertical]) {
            Image(nsImage: image).resizable().scaledToFit().padding(18)
              .frame(width: geometry.size.width * zoom, height: geometry.size.height * zoom)
          }
        } else {
          if loading {
            ProgressView("Loading preview…").frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            Text("Preview unavailable").foregroundStyle(.secondary).frame(
              maxWidth: .infinity, maxHeight: .infinity)
          }
        }
      }
      HStack(spacing: 12) {
        Button {
          zoom = max(1, zoom - 0.5)
        } label: {
          Image(systemName: "minus.magnifyingglass")
        }.disabled(zoom <= 1)
        Button("Fit") { zoom = 1 }
        Button {
          zoom = min(4, zoom + 0.5)
        } label: {
          Image(systemName: "plus.magnifyingglass")
        }.disabled(zoom >= 4)
      }.buttonStyle(.borderless).font(.caption).padding(8)
    }.background(Color(white: 0.925))
  }
}

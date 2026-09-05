import AppKit
import PDFKit
import SwiftUI

struct PageThumbnail: View {
  let store: DraftStore?
  let page: StoredPage
  @State private var thumbnail: NSImage?
  var body: some View {
    Group {
      if let thumbnail {
        Image(nsImage: thumbnail).resizable().scaledToFit().rotationEffect(
          .degrees(Double(page.rotation)))
      } else {
        Image(systemName: "doc.text").foregroundStyle(.secondary)
      }
    }.frame(width: 33, height: 44)
      .onAppear { thumbnail = store?.thumbnail(page) }
  }
}

struct PagePreview: View {
  let document: PDFDocument?
  @State private var zoom: CGFloat = 1
  var body: some View {
    VStack(spacing: 0) {
      GeometryReader { geometry in
        if let page = document?.page(at: 0) {
          let image = page.thumbnail(of: NSSize(width: 1800, height: 2400), for: .mediaBox)
          ScrollView([.horizontal, .vertical]) {
            Image(nsImage: image).resizable().scaledToFit().padding(18)
              .frame(width: geometry.size.width * zoom, height: geometry.size.height * zoom)
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

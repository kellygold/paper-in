import PDFKit
import SwiftUI

struct SheetPreview: View {
  @ObservedObject var model: AppModel
  var body: some View {
    if model.pairedPreview, let sheet = model.selectedSheet, sheet.paired {
      HStack(spacing: 1) {
        side(sheet, index: 0)
        side(sheet, index: 1)
      }.background(Color.gray.opacity(0.3))
    } else {
      PagePreview(document: model.preview)
    }
  }
  private func side(_ sheet: SheetGroup, index: Int) -> some View {
    let page = sheet.page(side: index)
    return VStack(spacing: 0) {
      HStack {
        Text(index == 0 ? "FRONT" : "BACK").font(.system(size: 10, weight: .semibold)).tracking(1.2)
        Spacer()
        if let page, !page.removed {
          Button(model.selected == page.id ? "Selected" : "Edit this side") {
            model.select(page.id)
          }.buttonStyle(.borderless)
        }
      }.padding(12).background(model.selected == page?.id ? Color.green.opacity(0.09) : Color.white)
      if let page, !page.removed {
        PagePreview(document: model.sheetPreviews[page.id])
      } else {
        VStack(spacing: 12) {
          Image(systemName: "doc.badge.ellipsis").font(.largeTitle)
          Text(
            page?.removed == true
              ? "Side removed"
              : (model.scanner.busy ? "Waiting for this side…" : "Side not received"))
          if page?.removed == true {
            Text("Use Restore removed page to bring it back.").font(.caption)
          }
        }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).background(
          Color(white: 0.925))
      }
    }.frame(maxWidth: .infinity)
  }
}

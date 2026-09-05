import Foundation

struct SheetGroup: Identifiable {
  var id: String
  var pages: [StoredPage]
  var expectedSides: Int { pages.map { $0.expectedSides ?? 1 }.max() ?? 1 }
  var visible: [StoredPage] { pages.filter { !$0.removed } }
  var paired: Bool { expectedSides == 2 }
  func page(side: Int) -> StoredPage? { pages.first { ($0.side ?? 0) == side } }
  static func make(_ pages: [StoredPage]) -> [SheetGroup] {
    var groups: [SheetGroup] = []
    for page in pages {
      let id = page.sheetID ?? page.id
      if let index = groups.firstIndex(where: { $0.id == id }) {
        groups[index].pages.append(page)
      } else {
        groups.append(SheetGroup(id: id, pages: [page]))
      }
    }
    return groups.filter { !$0.visible.isEmpty }
  }
}

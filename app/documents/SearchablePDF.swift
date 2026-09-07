import AppKit
import CoreText
import PDFKit

enum SearchablePDF {
  // PDFKit's whole-page OCR can miss text on very tall/narrow pages. Ordinary
  // pages use its native export; long pages retain their image and get tiled OCR.
  static func data(
    for document: PDFDocument, imageForPage: (Int) throws -> CGImage
  ) throws -> Data {
    let ordinary = PDFDocument()
    var ordinaryIndices: [Int: Int] = [:]
    for index in 0..<document.pageCount {
      let page = document.page(at: index)!
      let size = page.bounds(for: .mediaBox).size
      if max(size.width, size.height) <= 4 * min(size.width, size.height) {
        ordinaryIndices[index] = ordinary.pageCount
        ordinary.insert(page, at: ordinary.pageCount)
      }
    }
    let options: [PDFDocumentWriteOption: Any] = [.saveTextFromOCROption: true]
    var recognized: PDFDocument?
    if ordinary.pageCount > 0 {
      guard let data = ordinary.dataRepresentation(options: options),
        let pdf = PDFDocument(data: data), pdf.pageCount == ordinary.pageCount
      else { throw PaperError("Could not create the searchable PDF.") }
      recognized = pdf
    }
    let result = PDFDocument()
    for index in 0..<document.pageCount {
      if let ordinaryIndex = ordinaryIndices[index] {
        result.insert(recognized!.page(at: ordinaryIndex)!, at: index)
      } else {
        result.insert(
          try longPage(document.page(at: index)!, image: imageForPage(index)), at: index)
      }
    }
    // The filing helper must still measure recognition quality; embedded OCR
    // is not evidence that a scan contained perfectly reliable digital text.
    result.documentAttributes = [PDFDocumentAttribute.creatorAttribute: "Paper In (searchable PDF)"]
    guard let data = result.dataRepresentation() else {
      throw PaperError("Could not finish the searchable PDF.")
    }
    return data
  }

  private struct Line {
    let text: String
    let box: CGRect  // Full image pixels, bottom-left origin.
  }

  private static func longPage(_ original: PDFPage, image: CGImage) throws -> PDFPage {
    var lines: [Line] = []
    let height = image.height
    let stripHeight = min(4096, max(1024, image.width * 3))
    let overlap = 192
    // Overlap prevents a line at a strip boundary from being cut in half. Its
    // centre assigns it to one strip, so the exported text isn't repeated.
    for start in stride(from: 0, to: height, by: stripHeight) {
      try autoreleasepool {
        let top = max(0, start - overlap)
        let end = min(height, start + stripHeight)
        let bottom = min(height, end + overlap)
        guard
          let tile = image.cropping(
            to: CGRect(x: 0, y: top, width: image.width, height: bottom - top))
        else {
          throw PaperError("Could not read part of a long page.")
        }
        var error: NSError?
        guard let recognized = PIRecognizeText(tile, &error) else {
          throw error
            ?? NSError(
              domain: "PaperIn.OCR", code: 1,
              userInfo: [NSLocalizedDescriptionKey: "Could not recognize text on a long page."])
        }
        for observation in recognized {
          let text = observation.text
          let box = observation.box
          let centre = Double(top) + (1 - box.midY) * Double(bottom - top)
          guard centre >= Double(start), centre < Double(end) else { continue }
          lines.append(
            Line(
              text: text,
              box: CGRect(
                x: box.minX * Double(image.width),
                y: Double(height - bottom) + box.minY * Double(bottom - top),
                width: box.width * Double(image.width), height: box.height * Double(bottom - top))))
        }
      }
    }
    lines.sort {
      $0.box.midY == $1.box.midY ? $0.box.minX < $1.box.minX : $0.box.midY > $1.box.midY
    }

    // Draw the original PDF image without resampling or lossy conversion, then
    // write actual invisible PDF text. Rotation applies to both layers together.
    guard let source = original.pageRef else {
      throw PaperError("Could not read the original PDF page.")
    }
    var mediaBox = source.getBoxRect(.mediaBox)
    let bytes = NSMutableData()
    guard let consumer = CGDataConsumer(data: bytes),
      let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else { throw PaperError("Could not create a searchable long page.") }
    context.beginPDFPage(nil)
    context.drawPDFPage(source)
    let scaleX = mediaBox.width / Double(image.width)
    let scaleY = mediaBox.height / Double(image.height)
    for line in lines {
      let box = CGRect(
        x: mediaBox.minX + line.box.minX * scaleX, y: mediaBox.minY + line.box.minY * scaleY,
        width: line.box.width * scaleX, height: line.box.height * scaleY)
      let text = CTLineCreateWithAttributedString(
        NSAttributedString(
          string: line.text, attributes: [.font: NSFont.systemFont(ofSize: box.height)]))
      var ascent: CGFloat = 0
      var descent: CGFloat = 0
      let width = CTLineGetTypographicBounds(text, &ascent, &descent, nil)
      guard width > 0, ascent + descent > 0 else { continue }
      context.saveGState()
      context.translateBy(x: box.minX, y: box.minY)
      context.scaleBy(x: box.width / width, y: box.height / (ascent + descent))
      context.textMatrix = .identity
      context.textPosition = CGPoint(x: 0, y: descent)
      context.setTextDrawingMode(.invisible)
      CTLineDraw(text, context)
      context.restoreGState()
    }
    context.endPDFPage()
    context.closePDF()
    guard let page = PDFDocument(data: bytes as Data)?.page(at: 0) else {
      throw PaperError("Could not finish a searchable long page.")
    }
    page.rotation = original.rotation
    return page
  }
}

import AppKit
import SwiftUI
import PDFKit

@main enum BlankPreview {
  static func main() throws {
    precondition(CommandLine.arguments.contains("--demo"))
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let model = AppModel()
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 600,
      bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    memset(bitmap.bitmapData!,255,bitmap.bytesPerRow * bitmap.pixelsHigh)
    let blank = model.root.appendingPathComponent("blank.png")
    try bitmap.representation(using:.png,properties:[:])!.write(to:blank)
    model.skipBlankBacks = true
    try model.scanner.onBegin?(ScanOptions(duplex:true))
    try model.scanner.onPage?(model.root.appendingPathComponent("sample.tiff"),72)
    try model.scanner.onPage?(blank,300)
    model.scanner.onEnd?(true,nil)
    let skipped = model.selectedSheet!.page(side:1)!
    precondition(skipped.blankBackSkipped == true)
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1060,height:800),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
    window.title="Paper In — generated preview"
    window.appearance=NSAppearance(named:.aqua)
    window.contentView=NSHostingView(rootView:ContentView(model:model,scanner:model.scanner).environment(\.colorScheme,.light))
    window.makeKeyAndOrderFront(nil)
    func snapshot(_ name: String) {
      let view=window.contentView!
      let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
      view.cacheDisplay(in:view.bounds,to:bitmap)
      try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/blank-\(name).png"))
    }
    DispatchQueue.main.asyncAfter(deadline:.now()+2) {
      snapshot("skipped")
      model.edit { try $0.restore(skipped.id) }
      precondition(model.selectedSheet!.visible.count==2)
      DispatchQueue.main.asyncAfter(deadline:.now()+2) {
        snapshot("restored")
        try? FileManager.default.removeItem(at:model.root)
        print("PASS generated UI renders the skipped side and exact-side restoration")
        app.terminate(nil)
      }
    }
    withExtendedLifetime((model,window)) { app.run() }
  }
}

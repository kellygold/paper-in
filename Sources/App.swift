import AppKit
import Foundation
import PDFKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
  var model: AppModel!
  var window: NSWindow!
  var statusItem: NSStatusItem!
  func applicationDidFinishLaunching(_ notification: Notification) {
    model = AppModel()
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1060, height: 800),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.appearance = NSAppearance(named: .aqua)
    window.title = "Paper In"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(
      rootView: ContentView(model: model, scanner: model.scanner).environment(\.colorScheme, .light)
    )
    window.minSize = NSSize(width: 920, height: 740)
    window.center()
    window.makeKeyAndOrderFront(nil)
    let appMenu = NSMenu()
    let rootItem = NSMenuItem()
    appMenu.addItem(rootItem)
    let actions = NSMenu()
    rootItem.submenu = actions
    actions.addItem(
      withTitle: "About Paper In",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    actions.addItem(.separator())
    actions.addItem(
      withTitle: "Quit Paper In", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
    )
    NSApp.mainMenu = appMenu
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.button?.image = NSImage(
      systemSymbolName: "scanner", accessibilityDescription: "Paper In")
    let menu = NSMenu()
    for (title, action) in [
      ("Show Paper In", #selector(show)), ("Scan next page", #selector(scan)),
      ("Save PDF", #selector(save)), ("Show connection log", #selector(showLog)),
    ] {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit Paper In", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
    )
    statusItem.menu = menu
    model.scanner.diagnostics.event("window_opened")
    if !model.demo && CommandLine.arguments.contains("--connect") { model.scanner.connect() }
    NSApp.activate(ignoringOtherApps: true)
  }
  @objc func show() {
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  @objc func scan() { model.scan() }
  @objc func save() { model.save() }
  @objc func showLog() {
    NSWorkspace.shared.activateFileViewerSelecting([model.scanner.diagnostics.url])
  }
  func validateMenuItem(_ item: NSMenuItem) -> Bool {
    if item.action == #selector(scan) {
      return model.canEdit && (model.demo || model.scanner.connected)
    }
    if item.action == #selector(save) {
      return !model.scanner.busy && !model.exporting && !model.pages.isEmpty
    }
    return true
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    show()
    return true
  }
  func applicationWillTerminate(_ notification: Notification) {
    model?.scanner.pause()
    model?.filing.stop()
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main enum PaperInApp {
  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
  }
}

import Foundation
import ImageCaptureCore

final class FakeBrowser: ICDeviceBrowser {
  var starts = 0
  var stops = 0
  override func start() { starts += 1 }
  override func stop() { stops += 1 }
}
final class FakeScanner: ICScannerDevice {
  var opens = 0
  var closes = 0
  override var name: String? { "Brother DS-940DW" }
  override var serialNumberString: String? { "FAKE-DEVICE-NO-HARDWARE" }
  override var hasOpenSession: Bool { false }
  override func requestOpenSession() { opens += 1 }
  override func requestCloseSession() { closes += 1 }
}
let root = FileManager().temporaryDirectory.appendingPathComponent(
  "PaperIn-ConnectionTests-\(UUID().uuidString)")
defer { try? FileManager().removeItem(at: root) }
let defaultsName = "PaperIn.ConnectionTests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: defaultsName)!
defer { defaults.removePersistentDomain(forName: defaultsName) }
let browser = FakeBrowser()
let device = FakeScanner()
let controller = ScannerController(
  staging: root.appendingPathComponent("transfers"), defaults: defaults, browserFactory: { browser }
)
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  guard condition() else { fatalError(message) }
}
controller.connect()
controller.deviceBrowser(browser, didAdd: device, moreComing: false)
check(device.opens == 1, "Initial connection wasn't attempted")
controller.didRemove(device)
for _ in 0..<50 {
  controller.deviceBrowser(browser, didAdd: device, moreComing: false)
  controller.scannerDeviceDidBecomeAvailable(device)
}
check(
  device.opens == 1 && !controller.listening, "Device flapping caused repeated connection attempts")
print("PASS repeated device removal/addition pauses without a reconnect loop")
controller.connect()
controller.deviceBrowser(browser, didAdd: device, moreComing: false)
check(device.opens == 2, "Explicit Connect didn't re-arm discovery")
controller.device(device, didOpenSessionWithError: NSError(domain: "Test", code: -21345))
for _ in 0..<50 { controller.scannerDeviceDidBecomeAvailable(device) }
check(device.opens == 2 && !controller.listening, "Failed connection triggered automatic retries")
print("PASS open failure requires an explicit retry")
controller.pause()
print("Connection tests passed using fake browser/device; no scanner was contacted.")

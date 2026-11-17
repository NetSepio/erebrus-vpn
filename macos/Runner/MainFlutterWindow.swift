import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // The app UI is dark-only. A dark appearance keeps native chrome
    // consistent and makes WKWebView report prefers-color-scheme: dark to
    // pages in the in-app browser.
    NSApp.appearance = NSAppearance(named: .darkAqua)

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    if let delegate = NSApplication.shared.delegate as? AppDelegate {
      delegate.wireChannels(messenger: flutterViewController.engine.binaryMessenger)
    }

    super.awakeFromNib()
  }
}
import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private static let eventsChannel = "com.erebrus.vpn/events"
  private static let methodsChannel = "com.erebrus.vpn/methods"

  let linkStreamHandler = LinkStreamHandler()
  private var eventsChannelRef: FlutterEventChannel?
  private var methodsChannelRef: FlutterMethodChannel?
  var initialLink: String?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let url = NSAppleEventManager.shared().currentAppleEvent?
      .paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?
      .stringValue, url.hasPrefix("erebrusvpn://") {
      initialLink = url
    }
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in sender.windows where window.canBecomeMain {
        window.makeKeyAndOrderFront(self)
        return false
      }
    }
    return true
  }

  func wireChannels(messenger: FlutterBinaryMessenger) {
    SingboxBridge.shared.register(with: messenger)

    eventsChannelRef = FlutterEventChannel(
      name: AppDelegate.eventsChannel,
      binaryMessenger: messenger
    )
    eventsChannelRef?.setStreamHandler(linkStreamHandler)

    methodsChannelRef = FlutterMethodChannel(
      name: AppDelegate.methodsChannel,
      binaryMessenger: messenger
    )
    methodsChannelRef?.setMethodCallHandler { [weak self] call, result in
      if call.method == "initialLink" {
        if let link = self?.initialLink {
          _ = self?.linkStreamHandler.handleLink(link)
          self?.initialLink = nil
        }
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      if linkStreamHandler.handleLink(url.absoluteString) { continue }
      initialLink = url.absoluteString
    }
  }
}

final class LinkStreamHandler: NSObject, FlutterStreamHandler {
  var eventSink: FlutterEventSink?
  var queuedLinks = [String]()

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    queuedLinks.forEach { events($0) }
    queuedLinks.removeAll()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func handleLink(_ link: String) -> Bool {
    guard let eventSink else {
      queuedLinks.append(link)
      return false
    }
    eventSink(link)
    return true
  }
}
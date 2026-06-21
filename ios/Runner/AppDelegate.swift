import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let eventsChannel = "com.erebrus.vpn/events"
  private static let methodsChannel = "com.erebrus.vpn/methods"

  let linkStreamHandler = LinkStreamHandler()
  private var eventsChannelRef: FlutterEventChannel?
  private var methodsChannelRef: FlutterMethodChannel?
  var initialLink: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let url = launchOptions?[.url] as? URL {
      initialLink = url.absoluteString
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    SingboxBridge.shared.register(with: engineBridge.applicationRegistrar.messenger())

    let messenger = engineBridge.applicationRegistrar.messenger()
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

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if linkStreamHandler.handleLink(url.absoluteString) {
      return true
    }
    return super.application(app, open: url, options: options)
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
       let url = userActivity.webpageURL {
      if !linkStreamHandler.handleLink(url.absoluteString) {
        initialLink = url.absoluteString
      }
      return true
    }
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }
}

class LinkStreamHandler: NSObject, FlutterStreamHandler {
  var eventSink: FlutterEventSink?
  var queuedLinks = [String]()

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    queuedLinks.forEach { events($0) }
    queuedLinks.removeAll()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  func handleLink(_ link: String) -> Bool {
    guard let eventSink = eventSink else {
      queuedLinks.append(link)
      return false
    }
    eventSink(link)
    return true
  }
}
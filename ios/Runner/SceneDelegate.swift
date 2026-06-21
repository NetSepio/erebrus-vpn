import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
      super.scene(scene, openURLContexts: URLContexts)
      return
    }
    for context in URLContexts {
      _ = appDelegate.linkStreamHandler.handleLink(context.url.absoluteString)
    }
  }
}
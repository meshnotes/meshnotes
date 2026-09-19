import UIKit
import Flutter
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    center.requestAuthorization(options: [.alert, .sound]) { granted, error in
        // Handle authorization status
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

/// iOS 27 / Xcode 27 require a UIScene lifecycle. Flutter 3.35.2's FlutterSceneDelegate only
/// copies a window that AppDelegate already created, so we load Main.storyboard ourselves.
/// The storyboard FlutterViewController takes the launch engine registered above.
class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if window != nil {
      return
    }
    guard let windowScene = scene as? UIWindowScene else {
      return
    }
    let storyboard = UIStoryboard(name: "Main", bundle: nil)
    let newWindow = UIWindow(windowScene: windowScene)
    newWindow.rootViewController = storyboard.instantiateInitialViewController()
    window = newWindow
    newWindow.makeKeyAndVisible()
  }
}

import UIKit
import Flutter
import UserNotifications
import WidgetKit

/// The widget reads a small shared snapshot rather than opening the application's SQLite database.
private final class RecentNotesBridge {
  static let shared = RecentNotesBridge()
  private var channel: FlutterMethodChannel?
  private var pendingLink: String?
  private var ready = false

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "xyz.meshnotes/recent_notes", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "takePendingLink":
        self.ready = true
        let link = self.pendingLink
        self.pendingLink = nil
        result(link)
      case "updateNotes":
        guard let raw = call.arguments as? String,
              let defaults = UserDefaults(suiteName: "group.xyz.meshnotes.meshnotes") else {
          result(FlutterError(code: "widget_storage", message: "Shared widget storage is unavailable", details: nil))
          return
        }
        defaults.set(raw, forKey: "recent_notes")
        WidgetCenter.shared.reloadTimelines(ofKind: "RecentNotesWidget")
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  @discardableResult func receive(_ url: URL) -> Bool {
    guard url.scheme == "meshnotes", url.host == "widget" else { return false }
    if ready {
      channel?.invokeMethod("openLink", arguments: url.absoluteString)
    } else {
      pendingLink = url.absoluteString
    }
    return true
  }
}

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
    if let registrar = registrar(forPlugin: "RecentNotesBridge") {
      RecentNotesBridge.shared.register(messenger: registrar.messenger())
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    if RecentNotesBridge.shared.receive(url) { return true }
    return super.application(app, open: url, options: options)
  }
}

/// iOS 27 / Xcode 27 require a UIScene lifecycle. Flutter 3.35.2's FlutterSceneDelegate only
/// copies a window that AppDelegate already created, so we load Main.storyboard ourselves.
/// The storyboard FlutterViewController takes the launch engine registered above.
class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for context in connectionOptions.urlContexts { RecentNotesBridge.shared.receive(context.url) }
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

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let otherContexts = Set(URLContexts.filter { !RecentNotesBridge.shared.receive($0.url) })
    if !otherContexts.isEmpty { super.scene(scene, openURLContexts: otherContexts) }
  }
}

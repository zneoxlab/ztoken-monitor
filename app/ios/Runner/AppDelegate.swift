import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UNUserNotificationCenterDelegate {
  private static let notificationChannelName = "com.zneox.ztoken_monitor/notifications"
  private static let pushTokenKey = "remotePush.apnsToken"
  private static let openedEventKey = "remotePush.openedEvent"
  private static let eventKeys = [
    "eventId",
    "eventType",
    "type",
    "route",
    "targetId",
    "windowId",
    "cycleId",
    "remainingPercent",
    "thresholdPercent",
  ]

  private var notificationChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    if let userInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
      rememberOpenedPushEvent(userInfo)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    // 用户可能从系统设置返回并刚刚授权；重新注册可取得/刷新 APNs token。
    // Dart 仍会在至少一条配额规则启用时才把回调令牌上传 Hub。
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let granted: Bool
      if #available(iOS 14.0, *) {
        granted = settings.authorizationStatus == .authorized
          || settings.authorizationStatus == .provisional
          || settings.authorizationStatus == .ephemeral
      } else if #available(iOS 12.0, *) {
        granted = settings.authorizationStatus == .authorized
          || settings.authorizationStatus == .provisional
      } else {
        granted = settings.authorizationStatus == .authorized
      }
      if granted {
        DispatchQueue.main.async {
          application.registerForRemoteNotifications()
        }
      }
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: Self.notificationChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    notificationChannel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "requestPermission":
        UNUserNotificationCenter.current().requestAuthorization(
          options: [.alert, .sound, .badge]
        ) { granted, _ in
          DispatchQueue.main.async {
            if granted {
              UIApplication.shared.registerForRemoteNotifications()
            }
            result(granted)
          }
        }
      case "getNotificationPermissionStatus":
        UNUserNotificationCenter.current().getNotificationSettings { settings in
          let granted: Bool
          if #available(iOS 14.0, *) {
            granted = settings.authorizationStatus == .authorized
              || settings.authorizationStatus == .provisional
              || settings.authorizationStatus == .ephemeral
          } else if #available(iOS 12.0, *) {
            granted = settings.authorizationStatus == .authorized
              || settings.authorizationStatus == .provisional
          } else {
            granted = settings.authorizationStatus == .authorized
          }
          DispatchQueue.main.async {
            result(granted)
          }
        }
      case "getRemotePushToken":
        if let token = UserDefaults.standard.string(forKey: Self.pushTokenKey), !token.isEmpty {
          result(Self.pushTokenPayload(token))
        } else {
          DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
          }
          result(nil)
        }
      case "getInitialPushEvent":
        result(self.takeOpenedPushEvent())
      case "showQuotaNotification":
        guard
          let payload = call.arguments as? [String: Any],
          let title = payload["title"] as? String,
          let body = payload["body"] as? String,
          !title.isEmpty,
          !body.isEmpty
        else {
          result(
            FlutterError(
              code: "invalid_arguments",
              message: "通知内容无效",
              details: nil
            )
          )
          return
        }

        let identifier = (payload["tag"] as? String) ?? "quota-status"
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.add(
          UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
          )
        ) { error in
          DispatchQueue.main.async {
            if let error {
              result(
                FlutterError(
                  code: "notification_failed",
                  message: error.localizedDescription,
                  details: nil
                )
              )
            } else {
              result(nil)
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    guard !token.isEmpty else { return }
    UserDefaults.standard.set(token, forKey: Self.pushTokenKey)
    notificationChannel?.invokeMethod("pushTokenRefreshed", arguments: Self.pushTokenPayload(token))
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if let event = rememberOpenedPushEvent(response.notification.request.content.userInfo) {
      notificationChannel?.invokeMethod("pushNotificationOpened", arguments: event)
    }
    completionHandler()
  }

  private static func pushTokenPayload(_ token: String) -> [String: String] {
    let configured = Bundle.main.object(forInfoDictionaryKey: "ZTPushEnvironment") as? String
    let environment = configured == "development" ? "sandbox" : "production"
    return ["provider": "apns", "token": token, "environment": environment]
  }

  @discardableResult
  private func rememberOpenedPushEvent(_ userInfo: [AnyHashable: Any]) -> [String: String]? {
    guard let event = Self.pushEvent(from: userInfo),
      let data = try? JSONSerialization.data(withJSONObject: event),
      let encoded = String(data: data, encoding: .utf8)
    else {
      return nil
    }
    UserDefaults.standard.set(encoded, forKey: Self.openedEventKey)
    return event
  }

  private func takeOpenedPushEvent() -> [String: String]? {
    guard let encoded = UserDefaults.standard.string(forKey: Self.openedEventKey) else { return nil }
    UserDefaults.standard.removeObject(forKey: Self.openedEventKey)
    guard let data = encoded.data(using: .utf8),
      let value = try? JSONSerialization.jsonObject(with: data) as? [String: String]
    else {
      return nil
    }
    return value
  }

  private static func pushEvent(from userInfo: [AnyHashable: Any]) -> [String: String]? {
    let data = userInfo["data"] as? [String: Any]

    func stringValue(_ key: String) -> String? {
      let value = userInfo[key] ?? data?[key]
      switch value {
      case let value as String: value.trimmingCharacters(in: .whitespacesAndNewlines)
      case let value as NSNumber: value.stringValue
      default: nil
      }
    }

    let eventId = stringValue("eventId") ?? stringValue("event_id")
    guard let eventId, !eventId.isEmpty else { return nil }
    var event = ["eventId": eventId]
    for key in Self.eventKeys where key != "eventId" {
      if let value = stringValue(key), !value.isEmpty {
        event[key] = value
      }
    }
    return event
  }
}

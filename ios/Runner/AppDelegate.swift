import Flutter
import UIKit
import PushKit
import UserNotifications

#if canImport(flutter_callkit_incoming)
import flutter_callkit_incoming
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate {

    private var apnsTokenChannel: FlutterMethodChannel?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        // Setup MethodChannel for APNs token
        if let controller = window?.rootViewController as? FlutterViewController {
            apnsTokenChannel = FlutterMethodChannel(
                name: "com.gns.gcrumbs/push",
                binaryMessenger: controller.binaryMessenger
            )
        }

        let locale = Locale.current.regionCode ?? ""
        if locale != "CN" {
            let voipRegistry = PKPushRegistry(queue: DispatchQueue.main)
            voipRegistry.delegate = self
            voipRegistry.desiredPushTypes = [.voIP]

            #if canImport(flutter_callkit_incoming)
            SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
            #endif
        }

        // Request APNs permission
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - APNs Token
    override func application(_ application: UIApplication,
                               didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Foundation.Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("📲 APNs token: \(token)")
        apnsTokenChannel?.invokeMethod("onToken", arguments: token)
    }

    override func application(_ application: UIApplication,
                               didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ APNs registration failed: \(error)")
    }

    // MARK: - Foreground notification display
    override func userNotificationCenter(_ center: UNUserNotificationCenter,
                                         willPresent notification: UNNotification,
                                         withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // MARK: - PushKit Delegate (VoIP - unchanged)
    func pushRegistry(_ registry: PKPushRegistry,
                      didUpdate pushCredentials: PKPushCredentials,
                      for type: PKPushType) {
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        print("📲 VoIP token: \(token)")
        #if canImport(flutter_callkit_incoming)
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
        #endif
    }

    func pushRegistry(_ registry: PKPushRegistry,
                      didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType,
                      completion: @escaping () -> Void) {
        guard type == .voIP else { completion(); return }

        let data = payload.dictionaryPayload
        let gns = data["gns"] as? [String: Any]
        let callId = gns?["callId"] as? String ?? UUID().uuidString
        let callerPk = gns?["callerPk"] as? String ?? "Unknown"
        let callerHandle = gns?["callerHandle"] as? String
        let callerName = gns?["callerName"] as? String
        let callType = gns?["callType"] as? String ?? "voice"
        let displayName = callerName ?? (callerHandle.map { "@\($0)" }) ?? String(callerPk.prefix(12)) + "..."

        #if canImport(flutter_callkit_incoming)
        let callKitData = flutter_callkit_incoming.Data(id: callId, nameCaller: displayName, handle: callerHandle ?? String(callerPk.prefix(16)), type: callType == "video" ? 1 : 0)
        callKitData.duration = 45000
        callKitData.extra = ["callerPublicKey": callerPk, "callerHandle": callerHandle ?? "", "callType": callType]
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(callKitData, fromPushKit: true)
        #endif
        completion()
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        print("⚠️ VoIP push token invalidated")
    }
}

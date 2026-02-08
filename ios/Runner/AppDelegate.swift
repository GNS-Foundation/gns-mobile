import UIKit
import Flutter
import PushKit
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        
        // Register for VoIP pushes
        let voipRegistry = PKPushRegistry(queue: DispatchQueue.main)
        voipRegistry.delegate = self
        voipRegistry.desiredPushTypes = [.voIP]
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // MARK: - PushKit Delegate
    
    func pushRegistry(_ registry: PKPushRegistry, 
                      didUpdate pushCredentials: PKPushCredentials, 
                      for type: PKPushType) {
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        print("📲 VoIP token: \(token)")
        
        // flutter_callkit_incoming handles this automatically
        // but we explicitly pass it to be safe
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
    }
    
    func pushRegistry(_ registry: PKPushRegistry,
                      didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType,
                      completion: @escaping () -> Void) {
        guard type == .voIP else {
            completion()
            return
        }
        
        let data = payload.dictionaryPayload
        let gns = data["gns"] as? [String: Any]
        
        let callId = gns?["callId"] as? String ?? UUID().uuidString
        let callerPk = gns?["callerPk"] as? String ?? "Unknown"
        let callerHandle = gns?["callerHandle"] as? String
        let callerName = gns?["callerName"] as? String
        let callType = gns?["callType"] as? String ?? "voice"
        
        let displayName = callerName 
            ?? (callerHandle.map { "@\($0)" }) 
            ?? String(callerPk.prefix(12)) + "..."
        
        let callKitData = flutter_callkit_incoming.Data(id: callId, nameCaller: displayName, handle: callerHandle ?? String(callerPk.prefix(16)), type: callType == "video" ? 1 : 0)
        callKitData.duration = 45000
        callKitData.extra = [
            "callerPublicKey": callerPk,
            "callerHandle": callerHandle ?? "",
            "callType": callType,
        ]
        
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(
            callKitData,
            fromPushKit: true
        )
        
        completion()
    }
    
    func pushRegistry(_ registry: PKPushRegistry,
                      didInvalidatePushTokenFor type: PKPushType) {
        print("⚠️ VoIP push token invalidated")
    }
}

import SwiftUI
import UIKit

@main
struct LyricarApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        LyricTheme.cachingEnabled = true
        // Widget and Live Activity buttons can launch the app in the background with no
        // UI; register here so the command always has somewhere to go.
        PlaybackCommandRouter.handler = { action in
            await AppModel.shared.handle(action)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication {
            let configuration = UISceneConfiguration(name: "CarPlay", sessionRole: connectingSceneSession.role)
            configuration.delegateClass = CarPlaySceneDelegate.self
            return configuration
        }
        // The phone scene stays with SwiftUI.
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }
}

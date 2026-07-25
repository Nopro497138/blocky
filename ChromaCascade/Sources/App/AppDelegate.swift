import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Storage.registerDefaults()

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = GameViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        AudioManager.shared.stopMusic()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        AudioManager.shared.startMusic()
    }
}

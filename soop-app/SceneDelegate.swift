import UIKit

// tvOS 27 SDK 부터 UIScene 생명주기를 쓰지 않는 앱은 실행 직후 종료된다
// (UIKit `_UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption`).
// 창 생성을 AppDelegate 에서 이곳으로 옮겼다.
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = RootTabBarController()
        window.makeKeyAndVisible()
        self.window = window
    }
}

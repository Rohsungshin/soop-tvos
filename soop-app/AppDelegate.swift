import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = RootTabBarController()
        window.makeKeyAndVisible()
        self.window = window

        // .env 의 SOOP_ID / SOOP_PASSWORD 로 백그라운드 자동 로그인.
        // 성공 시 AuthTicket/UserTicket 쿠키가 HTTPCookieStorage 에 저장돼
        // 즐겨찾기·1080p 시도 같은 인증 필요한 API 호출에 자동 적용.
        SOOPAPIClient.shared.login { ok, err in
            if ok {
                print("[AppDelegate] auto-login OK")
            } else {
                print("[AppDelegate] auto-login FAILED: \(err ?? "")")
            }
        }
        return true
    }
}

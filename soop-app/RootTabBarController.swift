import UIKit

// MARK: - 루트 탭바 컨트롤러
//
// LIVE / 탐색 / MY 3개 탭. 각 탭은 UINavigationController로 감싸져
// 카테고리 → 방송 → 플레이어 식으로 깊이 진입 가능.

final class RootTabBarController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let liveNav = UINavigationController(rootViewController: LiveCategoriesViewController())
        liveNav.tabBarItem = UITabBarItem(title: "LIVE", image: nil, tag: 0)
        // tvOS에선 네비바를 숨기는 게 자연스럽다 — push/pop 자체는 작동
        liveNav.setNavigationBarHidden(true, animated: false)

        let exploreNav = UINavigationController(rootViewController: ExploreViewController())
        exploreNav.tabBarItem = UITabBarItem(title: "탐색", image: nil, tag: 1)
        exploreNav.setNavigationBarHidden(true, animated: false)

        let myNav = UINavigationController(rootViewController: MyViewController())
        myNav.tabBarItem = UITabBarItem(title: "MY", image: nil, tag: 2)
        myNav.setNavigationBarHidden(true, animated: false)

        viewControllers = [liveNav, exploreNav, myNav]
        selectedIndex = 0
    }
}

import UIKit

// MARK: - 루트 탭바 컨트롤러 (v2: 4탭)
//
// HOME / LIVE / 검색 / MY 4개 탭. 각 탭은 UINavigationController로 감싸져
// 카테고리 → 방송 → 플레이어 식으로 깊이 진입 가능.
// 다크 톤 통일, SOOP 브랜드 컬러로 선택 강조, SF Symbol 아이콘.

final class RootTabBarController: UITabBarController {

    private let brandLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Colors.background

        applyTabBarStyle()
        addBrandWordmark()

        let homeNav = makeNav(
            root: HomeViewController(),
            title: "HOME",
            image: UIImage(systemName: "house"),
            selected: UIImage(systemName: "house.fill"),
            tag: 0
        )
        let liveNav = makeNav(
            root: LiveCategoriesViewController(),
            title: "LIVE",
            image: UIImage(systemName: "dot.radiowaves.left.and.right"),
            selected: UIImage(systemName: "dot.radiowaves.left.and.right"),
            tag: 1
        )
        let searchNav = makeNav(
            root: SearchViewController(),
            title: "검색",
            image: UIImage(systemName: "magnifyingglass"),
            selected: UIImage(systemName: "magnifyingglass"),
            tag: 2
        )
        let myNav = makeNav(
            root: MyViewController(),
            title: "MY",
            image: UIImage(systemName: "person.circle"),
            selected: UIImage(systemName: "person.circle.fill"),
            tag: 3
        )

        viewControllers = [homeNav, liveNav, searchNav, myNav]
        selectedIndex = 0
    }

    private func makeNav(root: UIViewController,
                         title: String,
                         image: UIImage?,
                         selected: UIImage?,
                         tag: Int) -> UINavigationController {
        let nav = UINavigationController(rootViewController: root)
        let item = UITabBarItem(title: title, image: image, tag: tag)
        item.selectedImage = selected
        nav.tabBarItem = item
        nav.setNavigationBarHidden(true, animated: false)
        return nav
    }

    private func applyTabBarStyle() {
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: DS.Typography.subsection,
            .foregroundColor: DS.Colors.textSecondary,
        ]
        let selectedAttrs: [NSAttributedString.Key: Any] = [
            .font: DS.Typography.subsection,
            .foregroundColor: DS.Colors.textPrimary,
        ]
        UITabBarItem.appearance().setTitleTextAttributes(normalAttrs, for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes(selectedAttrs, for: .selected)
        UITabBarItem.appearance().setTitleTextAttributes(selectedAttrs, for: .focused)

        tabBar.barTintColor = DS.Colors.background
        tabBar.backgroundColor = DS.Colors.background
        tabBar.tintColor = DS.Colors.textPrimary
        tabBar.unselectedItemTintColor = DS.Colors.textSecondary
    }

    /// v3: 좌상단 SOOP 워드마크 — 브랜드 일관성
    private func addBrandWordmark() {
        brandLabel.text = "SOOP"
        brandLabel.textColor = DS.Colors.primary
        brandLabel.font = UIFont.systemFont(ofSize: 32, weight: .heavy)
        brandLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(brandLabel)
        NSLayoutConstraint.activate([
            brandLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DS.Spacing.xs),
            brandLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DS.Spacing.md),
        ])
    }
}

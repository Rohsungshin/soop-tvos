import UIKit

// MARK: - 탐색 탭
//
// 일단 placeholder — 추후 인기 BJ, 추천 카테고리, 검색 기능 추가 예정.

final class ExploreViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "탐색"

        let label = UILabel()
        label.text = "🔍 탐색\n\n준비 중입니다.\n(추후 인기 BJ·추천·검색)"
        label.textColor = .lightGray
        label.font = UIFont.systemFont(ofSize: 28, weight: .medium)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}

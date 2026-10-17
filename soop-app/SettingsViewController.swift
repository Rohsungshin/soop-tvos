import UIKit

// MARK: - 설정 화면 (v1)
//
// 5번째 탭. 현재는 '영상 플레이 방식' 하나만 노출한다:
//   • 자동 (화질 자동 전환) — AVPlayer의 ABR에 맡긴다. 끊김이 가장 적다.
//   • 고정 화질            — 고른 등급의 media playlist를 직접 재생해 전환 자체를 막는다.
//   • 네이티브 원본 (1080p) — SOOP 미디어 서버에서 원본을 직접 수신해 재생한다(docs/20261010).
//
// 저장소는 플레이어의 화질 메뉴와 공유한다(PlaybackSettings = `soop.player.quality`).
// 여기서 바꾼 값은 다음 재생부터 적용되고, 재생 중 트랜스포트 바에서 바꾼 값도 여기에 그대로 비친다.

final class SettingsViewController: UIViewController {

    private let titleLabel = UILabel()
    private var modeCards: [PlaybackMode: SettingsModeCard] = [:]
    private let qualityRow = SettingsQualityRow()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Colors.background
        setupTitle()
        setupModeCards()
        setupQualityRow()
        updateForCurrentSelection()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 재생 중 트랜스포트 바에서 화질을 바꾸고 돌아올 수 있으므로 들어올 때마다 현재 값으로 맞춘다
        updateForCurrentSelection()
    }

    private func setupTitle() {
        titleLabel.text = "설정"
        titleLabel.textColor = DS.Colors.textPrimary
        titleLabel.font = DS.Typography.hero
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DS.Layout.headerTopOffset),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DS.Layout.contentSideMargin),
        ])
    }

    private func setupModeCards() {
        let subtitle = UILabel()
        subtitle.text = "영상 플레이 방식"
        subtitle.textColor = DS.Colors.textSecondary
        subtitle.font = DS.Typography.subsection
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitle)
        NSLayoutConstraint.activate([
            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: DS.Spacing.md),
            subtitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DS.Layout.contentSideMargin),
        ])

        var previous: UIView = subtitle
        for mode in PlaybackMode.allCases {
            let card = SettingsModeCard(mode: mode)
            card.onSelect = { [weak self] selected in
                PlaybackSettings.mode = selected
                self?.updateForCurrentSelection()
            }
            modeCards[mode] = card
            view.addSubview(card)
            NSLayoutConstraint.activate([
                card.topAnchor.constraint(equalTo: previous.bottomAnchor, constant: DS.Spacing.sm),
                card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DS.Layout.contentSideMargin),
                card.widthAnchor.constraint(equalToConstant: 900),
            ])
            previous = card
        }
    }

    private func setupQualityRow() {
        qualityRow.onSelect = { [weak self] q in
            PlaybackSettings.quality = q
            self?.updateForCurrentSelection()
        }
        view.addSubview(qualityRow)
        guard let fixedCard = modeCards[.fixed] else { return }
        NSLayoutConstraint.activate([
            qualityRow.topAnchor.constraint(equalTo: fixedCard.bottomAnchor, constant: DS.Spacing.sm),
            qualityRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DS.Layout.contentSideMargin),
            qualityRow.widthAnchor.constraint(equalToConstant: 900),
        ])
    }

    private func updateForCurrentSelection() {
        let mode = PlaybackSettings.mode
        for (m, card) in modeCards {
            card.setSelected(m == mode)
        }
        // 고정 등급 행은 '고정 화질'에서만 의미가 있다. 자동·네이티브일 때는 흐리게.
        qualityRow.setDimmed(mode != .fixed)
        qualityRow.setSelected(PlaybackSettings.fixedQuality)
    }
}

// MARK: - 플레이 방식 카드

private final class SettingsModeCard: UIView {

    var onSelect: ((PlaybackMode) -> Void)?

    private let mode: PlaybackMode
    // tvOS의 system 버튼은 자체 배경(크롬)을 그린다. 카드 전체를 덮는 오버레이에 쓰면
    // 그 배경이 아래 깔린 제목·설명·체크를 가려 카드가 비어 보였다(2026-10-09 시뮬레이터 실측).
    // 배경을 그리지 않는 custom 타입을 쓰고, 무관하게 라벨이 항상 위에 오도록 버튼은 맨 아래에 깐다.
    private let button = UIButton(type: .custom)
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let checkIcon = UIImageView()
    private var selectedState = false

    init(mode: PlaybackMode) {
        self.mode = mode
        super.init(frame: .zero)

        backgroundColor = DS.Colors.surface
        layer.cornerRadius = DS.Corner.button
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = mode.label
        titleLabel.textColor = DS.Colors.textPrimary
        titleLabel.font = DS.Typography.cardTitle
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        detailLabel.text = mode.detail
        detailLabel.textColor = DS.Colors.textSecondary
        detailLabel.font = DS.Typography.caption
        detailLabel.numberOfLines = 2
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(detailLabel)

        checkIcon.image = UIImage(systemName: "checkmark.circle.fill")
        checkIcon.tintColor = DS.Colors.primary
        checkIcon.contentMode = .scaleAspectFit
        checkIcon.translatesAutoresizingMaskIntoConstraints = false
        checkIcon.isHidden = true
        addSubview(checkIcon)

        // 카드 전체를 덮는 투명 버튼이 포커스·선택을 받는다. 크기를 주지 않으면 0x0이라
        // 리모컨 포커스가 닿지 않아 카드를 고를 수 없다.
        button.backgroundColor = .clear
        button.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(button, at: 0)
        button.addTarget(self, action: #selector(didTap), for: .primaryActionTriggered)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 108),

            button.topAnchor.constraint(equalTo: topAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            checkIcon.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            checkIcon.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            checkIcon.widthAnchor.constraint(equalToConstant: 36),
            checkIcon.heightAnchor.constraint(equalToConstant: 36),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -80),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func didTap() {
        onSelect?(mode)
    }

    func setSelected(_ selected: Bool) {
        selectedState = selected
        checkIcon.isHidden = !selected
        backgroundColor = selected ? DS.Colors.surfaceElevated : DS.Colors.surface
        layer.borderWidth = selected ? 3 : 0
        layer.borderColor = selected ? DS.Colors.primary.cgColor : nil
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let focused = (context.nextFocusedView === button)
        coordinator.addCoordinatedAnimations {
            if self.selectedState {
                self.backgroundColor = DS.Colors.surfaceElevated
            } else {
                self.backgroundColor = focused ? DS.Colors.surfaceElevated : DS.Colors.surface
            }
            self.transform = focused ? CGAffineTransform(scaleX: 1.02, y: 1.02) : .identity
        }
    }
}

// MARK: - 고정 등급 행

private final class SettingsQualityRow: UIView {

    var onSelect: ((Int) -> Void)?

    private let titleLabel = UILabel()
    private let noteLabel = UILabel()
    private var buttons: [(quality: Int, button: UIButton)] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = "고정할 화질"
        titleLabel.textColor = DS.Colors.textSecondary
        titleLabel.font = DS.Typography.subcaption
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        noteLabel.text = "방송이 제공하는 화질만 적용됩니다. 국내 네트워크에서 SOOP 공개 스트리밍은 보통 540p·360p만 제공하므로 1080p·720p를 골라도 그 아래 최고 화질(보통 540p)로 고정됩니다"
        noteLabel.textColor = DS.Colors.textSecondary
        noteLabel.font = DS.Typography.caption
        noteLabel.numberOfLines = 3
        noteLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(noteLabel)

        var constraints: [NSLayoutConstraint] = [
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
        ]

        var previous: UIView?
        for quality in PlaybackSettings.fixedLadder {
            let b = makeQualityButton(title: QualityLadder.label(quality), quality: quality)
            buttons.append((quality, b))
            constraints += [
                b.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
                b.widthAnchor.constraint(equalToConstant: 180),
                b.heightAnchor.constraint(equalToConstant: 60),
                previous.map { b.leadingAnchor.constraint(equalTo: $0.trailingAnchor, constant: 16) }
                    ?? b.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            ]
            previous = b
        }

        if let last = buttons.last?.button {
            constraints += [
                noteLabel.topAnchor.constraint(equalTo: last.bottomAnchor, constant: 10),
                noteLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
                noteLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
                bottomAnchor.constraint(equalTo: noteLabel.bottomAnchor, constant: 4),
            ]
        }
        NSLayoutConstraint.activate(constraints)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeQualityButton(title: String, quality: Int) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = DS.Typography.body
        b.setTitleColor(DS.Colors.textPrimary, for: .normal)
        b.backgroundColor = DS.Colors.surface
        b.layer.cornerRadius = DS.Corner.badge + 6
        b.translatesAutoresizingMaskIntoConstraints = false
        b.tag = quality
        b.addTarget(self, action: #selector(didTapQuality(_:)), for: .primaryActionTriggered)
        addSubview(b)
        return b
    }

    @objc private func didTapQuality(_ sender: UIButton) {
        onSelect?(sender.tag)
    }

    func setSelected(_ quality: Int) {
        for (q, b) in buttons {
            let on = (q == quality)
            b.backgroundColor = on ? DS.Colors.primary : DS.Colors.surface
            b.setTitleColor(on ? .white : DS.Colors.textPrimary, for: .normal)
        }
    }

    /// '자동'일 때는 흐리게 하고 포커스도 받지 않게 한다(끄는 대신 남겨 둬서 무엇을 고를 수 있는지 보이게).
    func setDimmed(_ dimmed: Bool) {
        UIView.animate(withDuration: 0.25) {
            self.alpha = dimmed ? 0.25 : 1
        }
        for (_, b) in buttons {
            b.isUserInteractionEnabled = !dimmed
        }
    }
}

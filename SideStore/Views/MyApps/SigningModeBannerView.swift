//
//  SigningModeBannerView.swift
//  Catalyst
//
//  Card at the top of My Apps that explains how new apps get signed and lets the user switch
//  between the Apple ID certificate, the Enterprise certificate, or being asked each time.
//

import UIKit

final class SigningModeBannerView: UICollectionReusableView {
    static let reuseIdentifier = "SigningModeBanner"

    var onSelectPreference: ((SigningPreference) -> Void)?
    var onOpenEnterpriseSettings: (() -> Void)?
    var onPairDevice: (() -> Void)?

    private let cardView = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let changeButton = UIButton(type: .system)
    private let pairButton = UIButton(type: .system)
    private let buttonStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = UIColor(red: 0.078, green: 0.047, blue: 0.125, alpha: 1)
        cardView.layer.cornerRadius = 18
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = UIColor.altPrimary.withAlphaComponent(0.25).cgColor
        addSubview(cardView)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .altPrimary
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0

        descriptionLabel.font = .preferredFont(forTextStyle: .footnote)
        descriptionLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        descriptionLabel.numberOfLines = 0

        var changeConfig = UIButton.Configuration.filled()
        changeConfig.baseBackgroundColor = .altPrimary
        changeConfig.baseForegroundColor = .white
        changeConfig.cornerStyle = .capsule
        changeConfig.title = NSLocalizedString("Sign With…", comment: "")
        changeConfig.image = UIImage(systemName: "signature")
        changeConfig.imagePadding = 6
        changeConfig.buttonSize = .small
        changeButton.configuration = changeConfig
        #if !os(tvOS)
        changeButton.showsMenuAsPrimaryAction = true
        #else
        changeButton.addAction(UIAction { [weak self] _ in self?.onOpenEnterpriseSettings?() }, for: .primaryActionTriggered)
        #endif

        var pairConfig = UIButton.Configuration.tinted()
        pairConfig.baseForegroundColor = .altPrimary
        pairConfig.baseBackgroundColor = .altPrimary
        pairConfig.cornerStyle = .capsule
        pairConfig.title = NSLocalizedString("Pair This Device", comment: "")
        pairConfig.image = UIImage(systemName: "iphone.radiowaves.left.and.right")
        pairConfig.imagePadding = 6
        pairConfig.buttonSize = .small
        pairButton.configuration = pairConfig
        pairButton.addAction(UIAction { [weak self] _ in self?.onPairDevice?() }, for: .primaryActionTriggered)

        buttonStack.axis = .horizontal
        buttonStack.spacing = 8
        buttonStack.alignment = .leading
        buttonStack.addArrangedSubview(changeButton)
        buttonStack.addArrangedSubview(pairButton)
        buttonStack.addArrangedSubview(UIView())

        let textStack = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel, buttonStack])
        textStack.axis = .vertical
        textStack.spacing = 6
        textStack.setCustomSpacing(12, after: descriptionLabel)
        textStack.translatesAutoresizingMaskIntoConstraints = false

        cardView.addSubview(iconView)
        cardView.addSubview(textStack)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            cardView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),

            iconView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            iconView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            textStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 14),
            textStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -14),
        ])
    }

    func configure(preference: SigningPreference, identity: EnterpriseSigningIdentity?, hasPairingFile: Bool) {
        let hasIdentity = identity != nil

        switch preference {
        case .enterprise where hasIdentity:
            iconView.image = UIImage(systemName: "building.2.fill")
            titleLabel.text = NSLocalizedString("Signing with Enterprise Certificate", comment: "")
            descriptionLabel.text = String(format: NSLocalizedString("New apps are signed with %@. No 7-day refresh and no 3-app limit.", comment: ""), identity?.team.name ?? "")
        case .ask where hasIdentity:
            iconView.image = UIImage(systemName: "questionmark.circle.fill")
            titleLabel.text = NSLocalizedString("Choose When Installing", comment: "")
            descriptionLabel.text = NSLocalizedString("Catalyst asks whether to use your Apple ID or Enterprise certificate each time you install an app.", comment: "")
        default:
            iconView.image = UIImage(systemName: "person.crop.circle.fill")
            titleLabel.text = NSLocalizedString("Signing with Apple ID", comment: "")
            descriptionLabel.text = hasIdentity
                ? NSLocalizedString("Apps refresh every 7 days. Switch to your Enterprise certificate to skip the 7-day refresh and the 3-app limit.", comment: "")
                : NSLocalizedString("Apps refresh every 7 days. Have an Enterprise certificate? Sign with Enterprise to skip the 7-day refresh and the 3-app limit.", comment: "")
        }

        pairButton.isHidden = hasPairingFile
        cardView.layer.borderColor = UIColor.altPrimary.withAlphaComponent(0.25).cgColor

        #if !os(tvOS)
        let options = SigningPreference.allCases.map { option in
            UIAction(title: option.displayName,
                     image: UIImage(systemName: option.systemImage),
                     state: (option == preference && (option == .appleID || hasIdentity)) ? .on : .off) { [weak self] _ in
                self?.onSelectPreference?(option)
            }
        }
        let settings = UIAction(title: NSLocalizedString("Enterprise Signing Settings…", comment: ""),
                                image: UIImage(systemName: "gearshape")) { [weak self] _ in
            self?.onOpenEnterpriseSettings?()
        }
        changeButton.menu = UIMenu(title: NSLocalizedString("Sign new apps with", comment: ""), children: [
            UIMenu(options: .displayInline, children: options),
            settings,
        ])
        #endif
    }
}

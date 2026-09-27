//
//  EnterpriseSigningView.swift
//  Catalyst
//
//  Settings screen for Enterprise signing: import a .p12 + .mobileprovision pair,
//  switch between Apple ID and Enterprise signing, and check certificate status.
//

import SwiftUI
import SideSign
import UniformTypeIdentifiers

@MainActor
final class EnterpriseSigningViewModel: ObservableObject {
    @Published var identity: EnterpriseSigningIdentity?
    @Published var isEnabled: Bool = false
    @Published var preference: SigningPreference = EnterpriseSigningManager.shared.preference
    @Published var offerPairing = false
    @Published var status: CertificateStatus?
    @Published var isCheckingStatus = false

    // Import form
    @Published var p12Data: Data?
    @Published var p12FileName: String?
    @Published var profileData: Data?
    @Published var profileFileName: String?
    @Published var password: String = ""
    @Published var errorMessage: String?
    @Published var toastMessage: String?

    init() {
        reload()
    }

    var canImport: Bool { p12Data != nil && profileData != nil }

    func reload() {
        identity = EnterpriseSigningManager.shared.identity
        isEnabled = EnterpriseSigningManager.shared.isEnabled && identity != nil
        preference = EnterpriseSigningManager.shared.preference
    }

    func setPreference(_ value: SigningPreference) {
        EnterpriseSigningManager.shared.preference = value
        reload()
        showToast(value.displayName)
    }

    func setEnabled(_ enabled: Bool) {
        EnterpriseSigningManager.shared.isEnabled = enabled
        reload()
        showToast(enabled
                  ? NSLocalizedString("Enterprise signing on", comment: "")
                  : NSLocalizedString("Apple ID signing on", comment: ""))
    }

    func loadFile(at url: URL, isProfile: Bool) {
        do {
            let data = try Data(contentsOf: url)
            if isProfile {
                _ = try ALTProvisioningProfile(data: data)
                profileData = data
                profileFileName = url.lastPathComponent
            } else {
                p12Data = data
                p12FileName = url.lastPathComponent
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importIdentity() {
        guard let p12Data, let profileData else { return }
        do {
            let imported = try EnterpriseSigningManager.shared.importIdentity(
                p12Data: p12Data,
                password: password,
                profileData: profileData
            )
            self.p12Data = nil; self.p12FileName = nil
            self.profileData = nil; self.profileFileName = nil
            self.password = ""
            self.errorMessage = nil
            reload()
            showToast(String(format: NSLocalizedString("Imported %@", comment: ""), imported.profile.name))
            checkStatus()
            // Catalyst: offer to create a pairing file so installs work right away.
            offerPairing = !PairingFileManager.shared.hasPairingFile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeIdentity() {
        EnterpriseSigningManager.shared.removeIdentity()
        status = nil
        reload()
    }

    func checkStatus() {
        guard identity != nil, !isCheckingStatus else { return }
        isCheckingStatus = true
        Task {
            let result = await EnterpriseSigningManager.shared.checkStatus()
            self.status = result
            self.isCheckingStatus = false
        }
    }

    func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            withAnimation { if self?.toastMessage == message { self?.toastMessage = nil } }
        }
    }
}

struct EnterpriseSigningView: View {
    weak var presentingViewController: UIViewController?

    @StateObject private var viewModel = EnterpriseSigningViewModel()
    @State private var showFileImporter = false
    @State private var importingProfile = false
    @State private var showRemoveConfirmation = false
    @State private var showPairing = false

    private var p12Types: [UTType] {
        ["p12", "pfx"].compactMap { UTType(filenameExtension: $0) } + [.pkcs12]
    }
    private var profileTypes: [UTType] {
        [UTType(filenameExtension: "mobileprovision")].compactMap { $0 }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    signingMethodSection
                    pairingSection
                    if let identity = viewModel.identity {
                        identitySection(identity)
                    }
                    importSection
                    notesSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(CatalystSettingsStyle.background.ignoresSafeArea())

            if let toast = viewModel.toastMessage {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            NavigationLink(destination: PairThisDeviceView(), isActive: $showPairing) { EmptyView() }
                .hidden()
        }
        .navigationTitle(NSLocalizedString("Signing Method", comment: ""))
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            viewModel.reload()
            viewModel.checkStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: EnterpriseSigningManager.didChangeNotification)) { _ in
            viewModel.reload()
        }
        #if !os(tvOS)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: importingProfile ? profileTypes : p12Types,
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            viewModel.loadFile(at: url, isProfile: importingProfile)
        }
        #endif
        .alert(NSLocalizedString("Generate a Pairing File?", comment: ""), isPresented: $viewModel.offerPairing) {
            SwiftUI.Button(NSLocalizedString("Generate", comment: "")) { showPairing = true }
            SwiftUI.Button(NSLocalizedString("Later", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("Catalyst needs a pairing file for this device to install apps. You can create one now, right on this device.", comment: ""))
        }
        .confirmationDialog(NSLocalizedString("Remove Enterprise Certificate?", comment: ""),
                            isPresented: $showRemoveConfirmation,
                            titleVisibility: .visible) {
            SwiftUI.Button(NSLocalizedString("Remove", comment: ""), role: .destructive) { viewModel.removeIdentity() }
            SwiftUI.Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("New installs will use your Apple ID again. The certificate and profile stay in Certificate and Profile Management, so apps already signed with them keep working.", comment: ""))
        }
    }

    // MARK: Sections

    private var signingMethodSection: some View {
        CatalystSettingsSection(header: NSLocalizedString("Sign New Apps With", comment: ""), footer: modeFooter) {
            ForEach(Array(SigningPreference.allCases.enumerated()), id: \.element) { index, option in
                if index > 0 { CatalystSettingsDivider() }
                let isAvailable = option == .appleID || viewModel.identity?.isExpired == false
                SwiftUI.Button {
                    if isAvailable {
                        viewModel.setPreference(option)
                    } else {
                        viewModel.showToast(NSLocalizedString("Import an enterprise certificate below first.", comment: ""))
                    }
                } label: {
                    CatalystSettingsRow(title: option.displayName,
                                        icon: option.systemImage,
                                        isChecked: viewModel.preference == option && isAvailable,
                                        titleColor: isAvailable ? .white : CatalystSettingsStyle.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var pairingSection: some View {
        CatalystSettingsSection(header: NSLocalizedString("Pairing", comment: ""),
                                footer: NSLocalizedString("Installing apps needs a pairing file for this device, whichever certificate you use.", comment: "")) {
            NavigationLink(destination: PairThisDeviceView()) {
                CatalystSettingsRow(title: NSLocalizedString("Generate Pairing File", comment: ""),
                                    icon: "iphone.radiowaves.left.and.right",
                                    value: PairingFileManager.shared.hasPairingFile()
                                        ? NSLocalizedString("Active", comment: "")
                                        : NSLocalizedString("Missing", comment: ""),
                                    showsChevron: true)
            }
            .buttonStyle(.plain)
        }
    }

    private func identitySection(_ identity: EnterpriseSigningIdentity) -> some View {
        CatalystSettingsSection(header: NSLocalizedString("Enterprise Certificate", comment: "")) {
            CatalystSettingsRow(title: NSLocalizedString("Profile", comment: ""), value: identity.profile.name)
            CatalystSettingsDivider()
            CatalystSettingsRow(title: NSLocalizedString("Type", comment: ""), value: identity.kind.displayName)
            CatalystSettingsDivider()
            CatalystSettingsRow(title: NSLocalizedString("Team", comment: ""), value: "\(identity.team.name) (\(identity.team.identifier))")
            CatalystSettingsDivider()
            CatalystSettingsRow(title: NSLocalizedString("App ID", comment: ""),
                                value: identity.profile.bundleIdentifier + (identity.profile.isWildcard ? " " + NSLocalizedString("(wildcard)", comment: "") : ""))
            CatalystSettingsDivider()
            CatalystSettingsRow(title: NSLocalizedString("Certificate", comment: ""), value: identity.certificate.name)
            CatalystSettingsDivider()
            CatalystSettingsRow(title: NSLocalizedString("Expires", comment: ""), value: expiryText(identity.expirationDate))
            CatalystSettingsDivider()
            SwiftUI.Button {
                viewModel.checkStatus()
            } label: {
                HStack {
                    CatalystSettingsRow(title: NSLocalizedString("Status", comment: ""))
                    statusView.padding(.trailing, 16)
                }
            }
            .buttonStyle(.plain)
            CatalystSettingsDivider()
            SwiftUI.Button {
                showRemoveConfirmation = true
            } label: {
                CatalystSettingsRow(title: NSLocalizedString("Remove Certificate", comment: ""), titleColor: .red)
            }
            .buttonStyle(.plain)
        }
    }

    private var importSection: some View {
        CatalystSettingsSection(
            header: viewModel.identity == nil
                ? NSLocalizedString("Import Enterprise Certificate", comment: "")
                : NSLocalizedString("Replace Enterprise Certificate", comment: ""),
            footer: viewModel.errorMessage ?? NSLocalizedString("Use the certificate (.p12) and provisioning profile (.mobileprovision) issued to you by your organization.", comment: ""),
            footerColor: viewModel.errorMessage == nil ? CatalystSettingsStyle.secondaryText : .red
        ) {
            SwiftUI.Button { pickFile(profile: false) } label: {
                CatalystSettingsRow(title: NSLocalizedString("Certificate (.p12)", comment: ""),
                                    icon: "key.fill",
                                    value: viewModel.p12FileName ?? NSLocalizedString("Choose…", comment: ""),
                                    showsChevron: true)
            }
            .buttonStyle(.plain)
            CatalystSettingsDivider()
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 24)
                SecureField(NSLocalizedString("Certificate Password", comment: ""), text: $viewModel.password)
                    .font(.system(size: 17))
                    .foregroundColor(.white)
                    .textContentType(.password)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            CatalystSettingsDivider()
            SwiftUI.Button { pickFile(profile: true) } label: {
                CatalystSettingsRow(title: NSLocalizedString("Profile (.mobileprovision)", comment: ""),
                                    icon: "doc.badge.gearshape",
                                    value: viewModel.profileFileName ?? NSLocalizedString("Choose…", comment: ""),
                                    showsChevron: true)
            }
            .buttonStyle(.plain)
            CatalystSettingsDivider()
            SwiftUI.Button {
                viewModel.importIdentity()
            } label: {
                CatalystSettingsRow(title: NSLocalizedString("Import & Use", comment: ""),
                                    icon: "square.and.arrow.down",
                                    titleColor: viewModel.canImport ? .accentColor : CatalystSettingsStyle.secondaryText)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canImport)
        }
    }

    private var notesSection: some View {
        CatalystSettingsSection(header: NSLocalizedString("Good to Know", comment: "")) {
            note("checkmark.shield", NSLocalizedString("After the first install, trust the developer in Settings › General › VPN & Device Management.", comment: ""))
            CatalystSettingsDivider()
            note("asterisk.circle", NSLocalizedString("Wildcard profiles (TEAMID.*) work best: apps keep their own bundle IDs and extensions.", comment: ""))
            CatalystSettingsDivider()
            note("arrow.triangle.2.circlepath", NSLocalizedString("Apps already installed keep the certificate they were signed with. Reinstall an app to switch.", comment: ""))
            CatalystSettingsDivider()
            note("exclamationmark.triangle", NSLocalizedString("If Apple revokes the certificate, apps signed with it stop opening. Only use a certificate you're authorized to use.", comment: ""))
        }
    }

    // MARK: Pieces

    private var modeFooter: String {
        switch viewModel.preference {
        case .enterprise where viewModel.identity != nil:
            return NSLocalizedString("Apps are signed with your enterprise certificate. No Apple ID, 3-app limit or 7-day refresh.", comment: "")
        case .ask where viewModel.identity != nil:
            return NSLocalizedString("Catalyst asks which certificate to use each time you install an app, before anything else.", comment: "")
        default:
            return viewModel.identity == nil
                ? NSLocalizedString("Apps are signed with your Apple ID. Import an enterprise certificate below to use Enterprise signing.", comment: "")
                : NSLocalizedString("Apps are signed with your Apple ID.", comment: "")
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if viewModel.isCheckingStatus {
            ProgressView()
        } else {
            switch viewModel.status {
            case .valid?:
                Label(NSLocalizedString("Valid", comment: ""), systemImage: "checkmark.seal.fill")
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(.green)
            case .revoked?:
                Label(NSLocalizedString("Revoked", comment: ""), systemImage: "xmark.seal.fill")
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(.red)
            case .expired?:
                Label(NSLocalizedString("Expired", comment: ""), systemImage: "clock.badge.xmark")
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(.orange)
            case nil:
                Text(NSLocalizedString("Tap to check", comment: ""))
                    .font(.system(size: 15)).foregroundColor(CatalystSettingsStyle.secondaryText)
            }
        }
    }

    private func note(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(Color.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func expiryText(_ date: Date) -> String {
        let formatted = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days < 0 { return formatted + " · " + NSLocalizedString("expired", comment: "") }
        return formatted + " · " + String(format: NSLocalizedString("%d days", comment: ""), days)
    }

    private func pickFile(profile: Bool) {
        importingProfile = profile
        #if !os(tvOS)
        showFileImporter = true
        #else
        guard let topVC = presentingViewController ?? UIApplication.shared.topViewController() else { return }
        TVWebFileTransferManager.shared.startImport(
            acceptedExtensions: profile ? ["mobileprovision"] : ["p12", "pfx"],
            title: profile ? "Import Provisioning Profile" : "Import Certificate",
            presentingVC: topVC
        ) { fileURL in
            guard let fileURL else { return }
            Task { @MainActor in viewModel.loadFile(at: fileURL, isProfile: profile) }
        }
        #endif
    }
}

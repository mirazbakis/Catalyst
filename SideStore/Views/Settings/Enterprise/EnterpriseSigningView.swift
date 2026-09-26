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
            List {
                modeSection
                if let identity = viewModel.identity {
                    identitySection(identity)
                }
                importSection
                notesSection
            }
            #if !os(tvOS)
            .listStyle(.insetGrouped)
            #endif
            .alert(NSLocalizedString("Generate a Pairing File?", comment: ""), isPresented: $viewModel.offerPairing) {
                SwiftUI.Button(NSLocalizedString("Generate", comment: "")) { showPairing = true }
                SwiftUI.Button(NSLocalizedString("Later", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("Catalyst needs a pairing file for this device to install apps. You can create one now, right on this device.", comment: ""))
            }

            if let toast = viewModel.toastMessage {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle(NSLocalizedString("Enterprise Signing", comment: ""))
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
        .background(
            NavigationLink(destination: PairThisDeviceView(), isActive: $showPairing) { EmptyView() }.hidden()
        )
        .alert(isPresented: $showRemoveConfirmation) {
            Alert(
                title: Text(NSLocalizedString("Remove Enterprise Identity?", comment: "")),
                message: Text(NSLocalizedString("New installs will use your Apple ID again. The certificate and profile stay in Certificate and Profile Management, so apps already signed with them keep working.", comment: "")),
                primaryButton: .destructive(Text(NSLocalizedString("Remove", comment: ""))) { viewModel.removeIdentity() },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: Sections

    private var modeSection: some View {
        Section(
            header: Text(NSLocalizedString("Sign New Apps With", comment: "")),
            footer: Text(modeFooter)
        ) {
            ForEach(SigningPreference.allCases, id: \.self) { option in
                SwiftUI.Button {
                    viewModel.setPreference(option)
                } label: {
                    HStack {
                        Label(option.displayName, systemImage: option.systemImage)
                            .foregroundColor(.primary)
                        Spacer()
                        if viewModel.preference == option {
                            Image(systemName: "checkmark").foregroundColor(.accentColor)
                        }
                    }
                }
                .disabled(option != .appleID && (viewModel.identity == nil || viewModel.identity?.isExpired == true))
            }
            NavigationLink(destination: PairThisDeviceView()) {
                Label(NSLocalizedString("Generate Pairing File", comment: ""), systemImage: "iphone.radiowaves.left.and.right")
            }
        }
    }

    private var modeFooter: String {
        switch viewModel.preference {
        case .enterprise:
            return NSLocalizedString("Apps are signed with your enterprise certificate. No Apple ID, 3-app limit or 7-day refresh.", comment: "")
        case .ask:
            return NSLocalizedString("Catalyst asks which certificate to use each time you install an app.", comment: "")
        case .appleID:
            return viewModel.identity == nil
                ? NSLocalizedString("Apps are signed with your Apple ID. Import an enterprise identity below to use Enterprise signing.", comment: "")
                : NSLocalizedString("Apps are signed with your Apple ID.", comment: "")
        }
    }

    private func identitySection(_ identity: EnterpriseSigningIdentity) -> some View {
        Section(header: Text(NSLocalizedString("Current Identity", comment: ""))) {
            row(NSLocalizedString("Profile", comment: ""), identity.profile.name)
            row(NSLocalizedString("Type", comment: ""), identity.kind.displayName)
            row(NSLocalizedString("Team", comment: ""), "\(identity.team.name) (\(identity.team.identifier))")
            row(NSLocalizedString("App ID", comment: ""), identity.profile.bundleIdentifier + (identity.profile.isWildcard ? "  " + NSLocalizedString("(wildcard)", comment: "") : ""))
            row(NSLocalizedString("Certificate", comment: ""), identity.certificate.name)
            row(NSLocalizedString("Expires", comment: ""), expiryText(identity.expirationDate))
            HStack {
                Text(NSLocalizedString("Status", comment: ""))
                Spacer()
                statusView
            }
            SwiftUI.Button(NSLocalizedString("Check Status", comment: "")) { viewModel.checkStatus() }
                .disabled(viewModel.isCheckingStatus)
            SwiftUI.Button(role: .destructive) {
                showRemoveConfirmation = true
            } label: {
                Text(NSLocalizedString("Remove Identity", comment: ""))
            }
        }
    }

    private var importSection: some View {
        Section(
            header: Text(viewModel.identity == nil
                ? NSLocalizedString("Import Identity", comment: "")
                : NSLocalizedString("Replace Identity", comment: "")),
            footer: Text(viewModel.errorMessage ?? NSLocalizedString("Use the certificate (.p12) and provisioning profile (.mobileprovision) issued to you by your organization.", comment: ""))
                .foregroundColor(viewModel.errorMessage == nil ? .secondary : .red)
        ) {
            SwiftUI.Button {
                pickFile(profile: false)
            } label: {
                fileRow(NSLocalizedString("Certificate (.p12)", comment: ""), viewModel.p12FileName, icon: "key.fill")
            }
            SecureField(NSLocalizedString("Certificate Password", comment: ""), text: $viewModel.password)
                .textContentType(.password)
                .autocorrectionDisabled()
            SwiftUI.Button {
                pickFile(profile: true)
            } label: {
                fileRow(NSLocalizedString("Profile (.mobileprovision)", comment: ""), viewModel.profileFileName, icon: "doc.badge.gearshape")
            }
            SwiftUI.Button(NSLocalizedString("Import & Enable", comment: "")) {
                viewModel.importIdentity()
            }
            .font(.headline)
            .disabled(!viewModel.canImport)
        }
    }

    private var notesSection: some View {
        Section(header: Text(NSLocalizedString("Good to Know", comment: ""))) {
            note("checkmark.shield", NSLocalizedString("After the first install, trust the developer in Settings › General › VPN & Device Management.", comment: ""))
            note("asterisk.circle", NSLocalizedString("Wildcard profiles (TEAMID.*) work best: apps keep their own bundle IDs and extensions. Explicit profiles rename every app to the profile's App ID.", comment: ""))
            note("arrow.triangle.2.circlepath", NSLocalizedString("Apps already installed keep the identity they were signed with. Reinstall an app to move it to Enterprise signing.", comment: ""))
            note("exclamationmark.triangle", NSLocalizedString("If Apple revokes the certificate, apps signed with it stop opening. Only use a certificate you're authorized to use.", comment: ""))
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private var statusView: some View {
        if viewModel.isCheckingStatus {
            ProgressView()
        } else {
            switch viewModel.status {
            case .valid?:
                Label(NSLocalizedString("Valid", comment: ""), systemImage: "checkmark.seal.fill").foregroundColor(.green)
            case .revoked?:
                Label(NSLocalizedString("Revoked", comment: ""), systemImage: "xmark.seal.fill").foregroundColor(.red)
            case .expired?:
                Label(NSLocalizedString("Expired", comment: ""), systemImage: "clock.badge.xmark").foregroundColor(.orange)
            case nil:
                Text(NSLocalizedString("Unknown", comment: "")).foregroundColor(.secondary)
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    private func fileRow(_ title: String, _ fileName: String?, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(fileName ?? NSLocalizedString("Choose…", comment: ""))
                .foregroundColor(fileName == nil ? .accentColor : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func note(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).font(.footnote).foregroundColor(.secondary)
        } icon: {
            Image(systemName: icon).foregroundColor(.accentColor)
        }
    }

    private func expiryText(_ date: Date) -> String {
        let formatted = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days < 0 { return formatted + " · " + NSLocalizedString("expired", comment: "") }
        return formatted + " · " + String(format: NSLocalizedString("%d days left", comment: ""), days)
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

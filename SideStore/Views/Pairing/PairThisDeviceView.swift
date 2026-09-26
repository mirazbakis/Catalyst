//
//  PairThisDeviceView.swift
//  Catalyst
//
//  Generates a pairing file for *this* iPhone/iPad on-device, so Catalyst can install apps
//  no matter how Catalyst itself was signed (Apple ID, Enterprise or Ad Hoc).
//
//  Catalyst advertises itself as a pairable host (minimuxer's wireless pairing service), the
//  user taps "Pair with Catalyst" in Settings › Privacy & Security › Developer Mode and enters
//  the code, and the resulting pairing file is activated automatically. The flow is modelled
//  on StikPair's UX, but uses Catalyst's own minimuxer implementation (no StikPair code).
//
//  NOTE: needs proper testing on iOS 27 devices.
//

import SwiftUI
import UserNotifications

@MainActor
final class PairThisDeviceViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checkingPermission
        case waiting
        case pin(String)
        case success(deviceName: String)
        case failed(String)
    }

    static let hostName = "Catalyst"

    @Published var phase: Phase = .idle
    @Published var keepAliveInBackground = true
    @Published var exportURL: URL?
    @Published var isExportPresented = false
    @Published private(set) var hasPairingFile = PairingFileManager.shared.hasPairingFile()

    var isRunning: Bool {
        switch phase {
        case .checkingPermission, .waiting, .pin: return true
        default: return false
        }
    }

    func refresh() {
        hasPairingFile = PairingFileManager.shared.hasPairingFile()
    }

    func start() {
        guard !isRunning else { return }
        phase = .checkingPermission
        exportURL = nil

        Task { @MainActor in
            guard await LocalNetworkPermissionChecker.shared.checkPermission() else {
                self.phase = .failed(NSLocalizedString("Local Network access is required. Turn it on in Settings › Catalyst › Local Network, then try again.", comment: ""))
                return
            }
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            if self.keepAliveInBackground {
                _ = BackgroundAudioService.shared.start()
            }
            self.phase = .waiting
            self.startHost()
        }
    }

    func cancel() {
        wirelessPairing.stop()
        stopKeepAlive()
        phase = .idle
    }

    private func startHost() {
        wirelessPairing.onReadyToPair = { _, _ in
            debugLog("[PairThisDevice] Advertising as '\(PairThisDeviceViewModel.hostName)'")
        }
        wirelessPairing.onPinReceived = { [weak self] pin in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                self.phase = .pin(pin)
                Self.notify(id: "catalyst.pairing.pin",
                            title: NSLocalizedString("Catalyst pairing code", comment: ""),
                            body: String(format: NSLocalizedString("Enter %@ in Developer Mode › Pair with Catalyst.", comment: ""), pin))
            }
        }

        let docsPath = FileManager.default.documentsDirectory.path
        wirelessPairing.start(
            hostName: Self.hostName,
            outPath: docsPath,
            resolveFileName: { name, model in
                WirelessPairViewModel.pairingFileName(for: name, model: model)
            }
        ) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.stopKeepAlive()
                guard self.isRunning else { return }   // cancelled

                switch result {
                case .success(let device):
                    let url = URL(fileURLWithPath: device.pairingFilePath)
                    do {
                        try PairingFileManager.shared.importPairingFile(from: url)
                        self.exportURL = url
                        self.phase = .success(deviceName: device.name)
                        self.refresh()
                        Self.notify(id: "catalyst.pairing.done",
                                    title: NSLocalizedString("Pairing complete", comment: ""),
                                    body: NSLocalizedString("Catalyst can now install apps on this device.", comment: ""))
                    } catch {
                        self.phase = .failed(String(format: NSLocalizedString("Paired, but the pairing file couldn't be activated: %@", comment: ""), error.localizedDescription))
                    }
                case .failure(let error):
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func stopKeepAlive() {
        if BackgroundAudioService.shared.isRunning {
            BackgroundAudioService.shared.stop()
        }
    }

    private static func notify(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}

struct PairThisDeviceView: View {
    @StateObject private var viewModel = PairThisDeviceViewModel()
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [Color(red: 0.26, green: 0.13, blue: 0.45).opacity(0.30), .clear],
                           center: .top, startRadius: 0, endRadius: 380)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    statusCard
                    stepsCard
                    optionsCard
                    actionButtons
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle(NSLocalizedString("Pair This Device", comment: ""))
        .onAppear { viewModel.refresh() }
        .onDisappear { if viewModel.isRunning { viewModel.cancel() } }
        #if !os(tvOS)
        .sheet(isPresented: $viewModel.isExportPresented) {
            if let url = viewModel.exportURL {
                ActivityViewController(activityItems: [url])
            }
        }
        #endif
    }

    // MARK: Cards

    private var statusCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(viewModel.isRunning ? 0.25 : 0.12))
                    .frame(width: 96, height: 96)
                Image(systemName: statusIcon)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundColor(statusColor)
            }

            Text(statusTitle)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            if case .pin(let pin) = viewModel.phase {
                Text(pin)
                    .font(.system(size: 44, weight: .heavy, design: .monospaced))
                    .kerning(6)
                    .foregroundColor(.white)
                    .padding(.vertical, 6)
                    .textSelection(.enabled)
            }

            Text(statusDetail)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                Image(systemName: viewModel.hasPairingFile ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundColor(viewModel.hasPairingFile ? .green : .orange)
                Text(viewModel.hasPairingFile
                     ? NSLocalizedString("A pairing file is active", comment: "")
                     : NSLocalizedString("No pairing file yet", comment: ""))
                    .font(.footnote.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(card)
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(NSLocalizedString("HOW IT WORKS", comment: ""))
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            step(1, NSLocalizedString("Tap Start Pairing and allow Local Network access.", comment: ""))
            step(2, NSLocalizedString("Open Settings › Privacy & Security › Developer Mode, scroll down and tap Pair with Catalyst.", comment: ""))
            step(3, NSLocalizedString("Enter the code shown here (it's also sent as a notification).", comment: ""))
            step(4, NSLocalizedString("Come back. The pairing file is saved and activated automatically.", comment: ""))
            Text(NSLocalizedString("Works whether Catalyst is signed with an Apple ID, Enterprise or Ad Hoc certificate. Needs iOS 27 or later with Developer Mode on, and LocalDevVPN connected.", comment: ""))
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(card)
    }

    private var optionsCard: some View {
        Toggle(isOn: $viewModel.keepAliveInBackground) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Keep running in background", comment: ""))
                    .font(.body.weight(.semibold))
                Text(NSLocalizedString("Plays silent audio so pairing keeps waiting while you're in Settings.", comment: ""))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .disabled(viewModel.isRunning)
        .padding(18)
        .background(card)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if viewModel.isRunning {
                SwiftUI.Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    primaryLabel(NSLocalizedString("Open Settings", comment: ""), icon: "gear")
                }
                SwiftUI.Button(role: .destructive) {
                    viewModel.cancel()
                } label: {
                    Text(NSLocalizedString("Cancel", comment: "")).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            } else {
                SwiftUI.Button {
                    viewModel.start()
                } label: {
                    primaryLabel(viewModel.hasPairingFile
                                 ? NSLocalizedString("Generate New Pairing File", comment: "")
                                 : NSLocalizedString("Start Pairing", comment: ""),
                                 icon: "iphone.radiowaves.left.and.right")
                }
                if viewModel.exportURL != nil {
                    SwiftUI.Button {
                        viewModel.isExportPresented = true
                    } label: {
                        Label(NSLocalizedString("Export Pairing File", comment: ""), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                }
            }
        }
    }

    // MARK: Pieces

    private var card: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(red: 0.078, green: 0.047, blue: 0.125))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1))
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor.opacity(0.6)))
            Text(text).font(.subheadline)
        }
    }

    private func primaryLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor))
    }

    private var statusIcon: String {
        switch viewModel.phase {
        case .idle: return "iphone.radiowaves.left.and.right"
        case .checkingPermission, .waiting: return "antenna.radiowaves.left.and.right"
        case .pin: return "number"
        case .success: return "checkmark.seal.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch viewModel.phase {
        case .success: return .green
        case .failed: return .orange
        default: return .accentColor
        }
    }

    private var statusTitle: String {
        switch viewModel.phase {
        case .idle: return NSLocalizedString("Generate a Pairing File", comment: "")
        case .checkingPermission: return NSLocalizedString("Checking Local Network…", comment: "")
        case .waiting: return NSLocalizedString("Waiting for this device…", comment: "")
        case .pin: return NSLocalizedString("Enter this code in Settings", comment: "")
        case .success: return NSLocalizedString("Paired!", comment: "")
        case .failed: return NSLocalizedString("Pairing Failed", comment: "")
        }
    }

    private var statusDetail: String {
        switch viewModel.phase {
        case .idle:
            return NSLocalizedString("Catalyst needs a pairing file for this device to install and refresh apps.", comment: "")
        case .checkingPermission:
            return NSLocalizedString("Allow Local Network access if asked.", comment: "")
        case .waiting:
            return NSLocalizedString("Go to Settings › Privacy & Security › Developer Mode and tap Pair with Catalyst.", comment: "")
        case .pin:
            return NSLocalizedString("Developer Mode › Pair with Catalyst", comment: "")
        case .success(let name):
            return String(format: NSLocalizedString("Paired with %@. The pairing file is active.", comment: ""), name)
        case .failed(let message):
            return message
        }
    }
}

//
//  EnterpriseSigningManager.swift
//  Catalyst
//
//  Enterprise signing: sign and install apps with the user's own
//  certificate (.p12) + provisioning profile (.mobileprovision), without an Apple ID.
//
//  Catalyst never ships, downloads or shares certificates. Users import the
//  signing identity their own organisation issued to them.
//
//  NOTE: needs proper testing on-device with real enterprise, ad hoc and wildcard profiles.
//

import Foundation
import SideSign

public struct EnterpriseSigningIdentity: Sendable {
    public let certificate: ALTCertificate
    public let profile: ALTProvisioningProfile

    public var team: ALTTeam { profile.signingTeam }
    public var kind: ImportedProfileKind { profile.kind }
    public var expirationDate: Date { min(profile.expirationDate, certificate.x509.expiryDate) }
    public var isExpired: Bool { expirationDate <= Date() }
}

public enum EnterpriseSigningError: LocalizedError {
    case invalidCertificate(underlying: Error)
    case missingPrivateKey
    case invalidProfile(underlying: Error)
    case uninstallableProfile(ImportedProfileKind)
    case certificateNotInProfile
    case expired(Date)

    public var errorDescription: String? {
        switch self {
        case .invalidCertificate(let error):
            return String(format: NSLocalizedString("The certificate could not be opened. Check the password. (%@)", comment: ""), error.localizedDescription)
        case .missingPrivateKey:
            return NSLocalizedString("The .p12 file does not contain a private key.", comment: "")
        case .invalidProfile(let error):
            return String(format: NSLocalizedString("The provisioning profile is invalid. (%@)", comment: ""), error.localizedDescription)
        case .uninstallableProfile(let kind):
            return String(format: NSLocalizedString("%@ profiles can't be used to install apps. Use an Enterprise, Ad Hoc or Development profile.", comment: ""), kind.displayName)
        case .certificateNotInProfile:
            return NSLocalizedString("This certificate is not included in the provisioning profile. Import the matching .p12 and .mobileprovision pair.", comment: "")
        case .expired(let date):
            return String(format: NSLocalizedString("This signing identity expired on %@.", comment: ""), DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none))
        }
    }
}

public final class EnterpriseSigningManager: @unchecked Sendable {
    public static let shared = EnterpriseSigningManager()
    public static let didChangeNotification = Notification.Name("Catalyst.EnterpriseSigningDidChange")

    private let enabledKey = "catalystEnterpriseSigningEnabled"
    private let profileUUIDKey = "catalystEnterpriseProfileUUID"
    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - State

    /// User-facing switch. Only takes effect when a valid identity is imported.
    public var isEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set {
            defaults.set(newValue, forKey: enabledKey)
            notifyChange()
        }
    }

    public var profileUUID: String? {
        defaults.string(forKey: profileUUIDKey)
    }

    /// The imported identity, whether or not Enterprise mode is switched on.
    public var identity: EnterpriseSigningIdentity? {
        guard let uuid = profileUUID,
              let profile = ProfileManager.shared.getProfile(uuidString: uuid),
              let certificate = ProfileManager.shared.getMatchingCertificate(for: profile)
        else { return nil }
        return EnterpriseSigningIdentity(certificate: certificate, profile: profile)
    }

    /// The identity used for new installs, or `nil` when Apple ID signing should be used.
    public var activeIdentity: EnterpriseSigningIdentity? {
        guard isEnabled, let identity, !identity.isExpired else { return nil }
        return identity
    }

    public var isActive: Bool { activeIdentity != nil }

    // MARK: - Import

    /// Validates and stores a certificate + profile pair and makes it the enterprise identity.
    @discardableResult
    public func importIdentity(p12Data: Data, password: String?, profileData: Data) throws -> EnterpriseSigningIdentity {
        let certificate: ALTCertificate
        do {
            certificate = try CertificateManager.parse(p12Data, password: (password?.isEmpty ?? true) ? nil : password)
        } catch {
            // Some exporters use an empty string rather than no password.
            do { certificate = try CertificateManager.parse(p12Data, password: password ?? "") }
            catch { throw EnterpriseSigningError.invalidCertificate(underlying: error) }
        }
        guard !certificate.privateKey.isEmpty else { throw EnterpriseSigningError.missingPrivateKey }

        let profile: ALTProvisioningProfile
        do { profile = try ALTProvisioningProfile(data: profileData) }
        catch { throw EnterpriseSigningError.invalidProfile(underlying: error) }

        guard profile.kind.isInstallable else { throw EnterpriseSigningError.uninstallableProfile(profile.kind) }
        guard Self.profile(profile, contains: certificate) else { throw EnterpriseSigningError.certificateNotInProfile }

        let identity = EnterpriseSigningIdentity(certificate: certificate, profile: profile)
        guard !identity.isExpired else { throw EnterpriseSigningError.expired(identity.expirationDate) }

        // Persist through the existing stores so the rest of the pipeline
        // (profile assignment, refresh, certificate lookup) keeps working unchanged.
        CertificateManager.shared.saveCertificate(certificate)
        try ProfileManager.shared.importProfile(data: profileData)

        defaults.set(profile.uuid.uuidString, forKey: profileUUIDKey)
        defaults.set(true, forKey: enabledKey)
        debugLog("[EnterpriseSigningManager] Imported identity: profile '\(profile.name)' (\(profile.kind.rawValue), team \(profile.teamIdentifier)), cert \(certificate.serialNumber)")
        notifyChange()
        return identity
    }

    /// Unlinks the identity. The certificate and profile stay in Certificate/Profile
    /// Management so apps already signed with them can still be refreshed.
    public func removeIdentity() {
        defaults.removeObject(forKey: profileUUIDKey)
        defaults.set(false, forKey: enabledKey)
        debugLog("[EnterpriseSigningManager] Removed enterprise identity")
        notifyChange()
    }

    // MARK: - Status

    /// Checks the certificate against Apple's OCSP responder.
    func checkStatus() async -> CertificateStatus? {
        guard let identity else { return nil }
        do {
            try await OCSPValidator.validate(identity.certificate.x509)
            return .valid(isCrossSigned: false)
        } catch OCSPValidationError.revoked {
            return .revoked
        } catch OCSPValidationError.expired {
            return .expired
        } catch {
            debugLog("[EnterpriseSigningManager] OCSP check inconclusive: \(error)")
            return nil
        }
    }

    // MARK: - Helpers

    static func profile(_ profile: ALTProvisioningProfile, contains certificate: ALTCertificate) -> Bool {
        func clean(_ serial: String) -> String {
            var s = serial.uppercased()
            if s.hasPrefix("0X") { s.removeFirst(2) }
            while s.hasPrefix("0") && s.count > 1 { s.removeFirst() }
            return s
        }
        let serial = clean(certificate.serialNumber)
        return profile.certificates.contains { embedded in
            clean(embedded.serialNumber) == serial || (embedded.data != nil && embedded.data == certificate.data)
        }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}

// MARK: - Team resolution

public extension AuthManager {
    /// The team new apps are signed for: the enterprise identity's team when
    /// Enterprise mode is active, otherwise the signed-in Apple ID team.
    func getSigningTeam() async throws -> ALTTeam {
        if let identity = EnterpriseSigningManager.shared.activeIdentity {
            return identity.team
        }
        return try await getAuthenticatedTeam()
    }
}

extension InstallAppOperationContext {
    /// Resolves the team for the profile this operation signs with.
    ///
    /// When the profile belongs to the signed-in Apple ID team, behaviour is unchanged.
    /// For imported profiles from another team (or with no Apple ID at all) the profile's
    /// own team is used, so no Apple ID session is required.
    func resolveSigningTeam() async throws -> ALTTeam {
        if let profile = overrideProvisioningProfile {
            if let authTeam = try? await AuthManager.shared.getAuthenticatedTeam(),
               authTeam.identifier == profile.teamIdentifier {
                return authTeam
            }
            return profile.signingTeam
        }
        return try await AuthManager.shared.getSigningTeam()
    }

    /// `true` when signing with a profile that isn't managed by the signed-in Apple ID,
    /// meaning the developer portal must not be contacted for it.
    func isSigningWithImportedIdentity() async -> Bool {
        guard let profile = overrideProvisioningProfile else { return false }
        guard let authTeam = try? await AuthManager.shared.getAuthenticatedTeam() else { return true }
        return authTeam.identifier != profile.teamIdentifier
    }

    /// Whether this pipeline re-signs the app bundle (install/update/resign) as opposed to
    /// only refreshing profiles of an already-signed app.
    var resignsAppBundle: Bool {
        pipelineSteps.contains { $0.step == .resignApp }
    }
}

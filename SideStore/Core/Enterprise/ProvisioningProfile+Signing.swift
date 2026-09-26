//
//  ProvisioningProfile+Signing.swift
//  Catalyst
//
//  Helpers for signing with imported (non Apple ID) provisioning profiles,
//  e.g. Enterprise / In-House, Ad Hoc and wildcard profiles.
//

import Foundation
import SideSign

/// The distribution type of a provisioning profile, derived from its plist.
public enum ImportedProfileKind: String, Sendable {
    case enterprise     // ProvisionsAllDevices = true (Apple Developer Enterprise Program, In-House)
    case adHoc          // ProvisionedDevices present, get-task-allow = false
    case development    // ProvisionedDevices present, get-task-allow = true
    case appStore       // No device list and not ProvisionsAllDevices -> cannot be sideloaded
    case free           // Xcode free (LocalProvision) profile

    public var displayName: String {
        switch self {
        case .enterprise:  return NSLocalizedString("Enterprise (In-House)", comment: "")
        case .adHoc:       return NSLocalizedString("Ad Hoc", comment: "")
        case .development: return NSLocalizedString("Development", comment: "")
        case .appStore:    return NSLocalizedString("App Store", comment: "")
        case .free:        return NSLocalizedString("Free Development", comment: "")
        }
    }

    /// Whether apps signed with this profile can be installed outside the App Store.
    public var isInstallable: Bool { self != .appStore }
}

public extension ALTProvisioningProfile {

    /// The decoded property list embedded in the CMS-signed .mobileprovision.
    ///
    /// The payload of a .mobileprovision is a plain XML plist wrapped in a CMS envelope,
    /// so it is enough to slice out `<?xml ... </plist>` and decode it.
    var decodedPlist: [String: Any]? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }

        let slice = data.subdata(in: start.lowerBound..<end.upperBound)
        return (try? PropertyListSerialization.propertyList(from: slice, options: [], format: nil)) as? [String: Any]
    }

    var provisionsAllDevices: Bool {
        (decodedPlist?["ProvisionsAllDevices"] as? Bool) ?? false
    }

    var kind: ImportedProfileKind {
        if isFreeProvisioningProfile { return .free }
        if provisionsAllDevices { return .enterprise }
        let plist = decodedPlist
        if let devices = plist?["ProvisionedDevices"] as? [String], !devices.isEmpty {
            let entitlements = plist?["Entitlements"] as? [String: Any]
            let getTaskAllow = (entitlements?["get-task-allow"] as? Bool) ?? false
            return getTaskAllow ? .development : .adHoc
        }
        return .appStore
    }

    /// `true` when the profile's App ID is a wildcard such as `TEAMID.*` or `TEAMID.com.company.*`.
    var isWildcard: Bool {
        bundleIdentifier.hasSuffix("*")
    }

    /// Whether `bundleID` is covered by this profile's App ID.
    func covers(bundleID: String) -> Bool {
        guard isWildcard else { return bundleIdentifier == bundleID }
        let prefix = String(bundleIdentifier.dropLast())   // "" for "*", "com.company." for "com.company.*"
        return prefix.isEmpty || bundleID.hasPrefix(prefix)
    }

    /// The bundle identifier an app signed with this profile will end up with.
    ///
    /// Explicit profiles force their own identifier (existing SideStore behaviour),
    /// wildcard profiles keep the requested identifier.
    func resolvedBundleIdentifier(for requestedBundleID: String) -> String {
        isWildcard ? requestedBundleID : bundleIdentifier
    }

    /// Profile entitlements with the wildcard `application-identifier` resolved for `bundleID`.
    func resolvedEntitlements(for bundleID: String) -> [String: any Sendable] {
        var entitlements = self.entitlements
        guard isWildcard else { return entitlements }

        let appID = "\(teamIdentifier).\(bundleID)"
        entitlements["application-identifier"] = appID
        if let groups = entitlements["keychain-access-groups"] as? [String] {
            entitlements["keychain-access-groups"] = groups.map { $0.hasSuffix("*") ? appID : $0 }
        }
        return entitlements
    }

    /// A team value describing the profile owner, used when signing without an Apple ID session.
    var signingTeam: ALTTeam {
        ALTTeam(identifier: teamIdentifier, name: teamName, type: .organization)
    }
}

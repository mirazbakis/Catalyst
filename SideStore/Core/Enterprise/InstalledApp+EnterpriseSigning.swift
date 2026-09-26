//
//  InstalledApp+EnterpriseSigning.swift
//  Catalyst
//
//  Detects apps signed with an enterprise (In-House) certificate, whether imported in
//  Catalyst's Enterprise mode or used by an external signing service to install Catalyst
//  itself. Those apps don't follow the 7-day free-account cycle, so the refresh timer,
//  expiry warnings and background refresh are hidden/skipped for them.
//
//  NOTE: needs proper testing with Catalyst installed through an external enterprise signer.
//

import Foundation
import SideSign

enum EnterpriseSigningDetector {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: Bool] = [:]

    /// `true` when the .mobileprovision data has `ProvisionsAllDevices = true`.
    static func isEnterpriseProfile(_ data: Data) -> Bool {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data.subdata(in: start.lowerBound..<end.upperBound), options: [], format: nil) as? [String: Any]
        else { return false }
        return (plist["ProvisionsAllDevices"] as? Bool) ?? false
    }

    static func isEnterpriseProfile(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        return isEnterpriseProfile(data)
    }

    /// Whether the running Catalyst binary itself was installed with an enterprise profile.
    static let isRunningAppEnterpriseSigned: Bool = {
        isEnterpriseProfile(at: Bundle.main.bundleURL.appendingPathComponent("embedded.mobileprovision"))
    }()

    /// Returns the cached value, or computes it. `compute` returns `nil` when no profile could be
    /// found yet (e.g. right after an install, before metadata is cached); that result isn't cached.
    static func cachedValue(for key: String, compute: () -> Bool?) -> Bool {
        if let value = lock.withLock({ cache[key] }) { return value }
        guard let value = compute() else { return false }
        lock.withLock { cache[key] = value }
        return value
    }

    static func invalidate() {
        lock.withLock { cache.removeAll() }
    }
}

extension InstalledApp {
    /// `true` when this app is signed with an enterprise (In-House) profile.
    var isEnterpriseSigned: Bool {
        if self.bundleIdentifier == StoreApp.altstoreAppID {
            return EnterpriseSigningDetector.isRunningAppEnterpriseSigned
        }

        // Cache per install/refresh so collection view cells don't re-read profiles on every reload.
        let key = "\(self.resignedBundleIdentifier)|\(self.refreshedDate.timeIntervalSince1970)"
        let customProfileURL = self.customProvisioningProfileURL
        let bundleIdentifier = self.bundleIdentifier
        let embeddedProfileURL = self.directoryURL.appendingPathComponent("App.app").appendingPathComponent("embedded.mobileprovision")

        return EnterpriseSigningDetector.cachedValue(for: key) {
            if let customProfileURL {
                return EnterpriseSigningDetector.isEnterpriseProfile(at: customProfileURL)
            }
            if let assigned = ProfileManager.shared.getAssignedProfile(for: bundleIdentifier) {
                return EnterpriseSigningDetector.isEnterpriseProfile(assigned.data)
            }
            guard FileManager.default.fileExists(atPath: embeddedProfileURL.path) else { return nil }
            return EnterpriseSigningDetector.isEnterpriseProfile(at: embeddedProfileURL)
        }
    }

    /// Hide the refresh countdown for enterprise-signed apps unless they're actually close to
    /// their (usually one-year) profile expiry.
    var hidesExpirationCountdown: Bool {
        guard self.isEnterpriseSigned else { return false }
        return self.expirationDate.timeIntervalSinceNow > 7 * 24 * 60 * 60
    }
}

//
//  EnterpriseAppSigner.swift
//  Catalyst
//
//  Signs an app bundle with an imported certificate + profile. Mirrors SideSign's
//  AppBundleSigner, but resolves wildcard App IDs (TEAMID.* / TEAMID.com.company.*)
//  into concrete `application-identifier` entitlements per bundle, which iOS requires.
//
//  NOTE: needs proper testing with apps that contain extensions and keychain groups.
//

import Foundation
import SideSign
import CodeSignKit

struct EnterpriseAppSigner: Sendable {
    let certificate: ALTCertificate

    func signApp(at appURL: URL, provisioningProfiles profiles: [ALTProvisioningProfile]) async throws {
        guard let appBundle = ALTApplication(fileURL: appURL) else {
            throw SignerError.invalidApp(cause: "Failed to parse app bundle at \(appURL.path)")
        }

        func profile(for app: ALTApplication) -> ALTProvisioningProfile? {
            profiles.first { !$0.isWildcard && $0.bundleIdentifier == app.bundleIdentifier }
                ?? profiles.first { $0.covers(bundleID: app.bundleIdentifier) }
                ?? profiles.first
        }

        var entitlementsByURL: [URL: String] = [:]

        func prepare(_ app: ALTApplication) throws {
            guard let matchedProfile = profile(for: app) else {
                throw SignerError.missingProvisioningProfile(bundleIdentifier: app.bundleIdentifier)
            }
            if matchedProfile.isWildcard && !matchedProfile.covers(bundleID: app.bundleIdentifier) {
                debugLog("[EnterpriseAppSigner] WARNING: '\(app.bundleIdentifier)' is outside wildcard App ID '\(matchedProfile.bundleIdentifier)'. Installation will likely fail.")
            }

            var entitlements = matchedProfile.resolvedEntitlements(for: app.bundleIdentifier)
            let appEntitlements = app.entitlements

            // Same filtering as SideSign: keep only what the app asks for, plus identity keys.
            for key in Array(entitlements.keys) {
                if let appValue = appEntitlements[key] {
                    if key == "keychain-access-groups", let groups = appValue as? [String] {
                        entitlements[key] = groups.map { group -> String in
                            guard let dot = group.firstIndex(of: ".") else { return "\(matchedProfile.teamIdentifier).\(group)" }
                            return matchedProfile.teamIdentifier + group[dot...]
                        }
                    }
                } else if key != "application-identifier"
                            && key != "com.apple.developer.team-identifier"
                            && key != "get-task-allow" {
                    entitlements.removeValue(forKey: key)
                }
            }

            let plist = try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0)
            guard let xml = String(data: plist, encoding: .utf8) else {
                throw SignerError.unknown(cause: "Failed to encode entitlements for \(app.bundleIdentifier)")
            }
            entitlementsByURL[app.fileURL.resolvingSymlinksInPath()] = xml

            // The embedded profile must be the original, Apple-signed file.
            try matchedProfile.data.write(to: app.fileURL.appendingPathComponent("embedded.mobileprovision"))
        }

        try prepare(appBundle)
        for appExtension in appBundle.appExtensions {
            try prepare(appExtension)
        }

        let keyData = try certificate.exportP12()
        let appRoot = appBundle.fileURL.resolvingSymlinksInPath()
        let extensionRoots = appBundle.appExtensions.map { $0.fileURL.resolvingSymlinksInPath() }
        let captured = entitlementsByURL

        try CodeSigner.sign(
            appPath: appBundle.fileURL.path,
            keyData: keyData,
            entitlementProvider: { path in
                let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return captured[appRoot] ?? "" }

                let url = trimmed.hasPrefix("/") ? URL(fileURLWithPath: trimmed) : appRoot.appendingPathComponent(trimmed)
                let resolved = url.resolvingSymlinksInPath()

                if resolved == appRoot { return captured[appRoot] ?? "" }
                if let ext = extensionRoots.first(where: { resolved == $0 || resolved.path.hasPrefix($0.path + "/") }) {
                    return captured[ext] ?? ""
                }
                // Frameworks and dylibs are signed without entitlements.
                if resolved.path.contains(".framework") || resolved.pathExtension.lowercased() == "dylib" {
                    return ""
                }
                // Main executable and other files directly in the app bundle.
                if resolved.path.hasPrefix(appRoot.path + "/") { return captured[appRoot] ?? "" }
                return ""
            },
            progress: {}
        )
        debugLog("[EnterpriseAppSigner] Signed \(appBundle.bundleIdentifier) with certificate \(certificate.serialNumber)")
    }
}

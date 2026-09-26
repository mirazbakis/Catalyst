//
//  UpdateAppCertificateOperation.swift
//  SideStore
//
//  Created by Magesh K on 1/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
import CoreData
import SideSign

final class UpdateAppCertificateOperation: BasePipelineOperation<InstallAppOperationContext, Void>, @unchecked Sendable {
    
    override func execute(parentProgress: Progress?) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[UpdateAppCertificateOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[UpdateAppCertificateOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        
        let targetBundleID = self.context.installedApp?.bundleIdentifier ?? self.context.targetBundleIdentifier
        var profileToUse = self.context.overrideProvisioningProfile ?? ProfileManager.shared.getAssignedProfile(for: targetBundleID)

        // Catalyst: Enterprise signing. Apps without an assigned profile are signed with the
        // imported enterprise identity when Enterprise mode is on. Only for pipelines that
        // re-sign the bundle; a profile-only refresh must keep the app's original identity.
        if profileToUse == nil, self.context.resignsAppBundle,
           let identity = EnterpriseSigningManager.shared.activeIdentity {
            debugLog("[UpdateAppCertificateOperation] Enterprise mode active. Using profile '\(identity.profile.name)' (\(identity.profile.uuid)) for '\(targetBundleID)'")
            profileToUse = identity.profile
            self.context.overrideSigningCertificate = identity.certificate
        }

        if let assignedProfile = profileToUse {
            debugLog("[UpdateAppCertificateOperation] Target bundle '\(targetBundleID)' using assigned profile: '\(assignedProfile.name)' (\(assignedProfile.uuid))")
            self.context.overrideProvisioningProfile = assignedProfile

            if self.context.overrideSigningCertificate != nil, EnterpriseSigningManager.shared.activeIdentity?.profile.uuid == assignedProfile.uuid {
                // Certificate already resolved from the enterprise identity above.
            } else if let matchingCert = ProfileManager.shared.getMatchingCertificate(for: assignedProfile) {
                debugLog("[UpdateAppCertificateOperation] Loaded matching certificate '\(matchingCert.serialNumber)' for assigned profile. Setting context.overrideSigningCertificate.")
                self.context.overrideSigningCertificate = matchingCert
            } else if let serialNumber = self.context.installedApp?.certificateSerialNumber,
                      let customCert = CertificateManager.shared.getSignableCertificate(for: serialNumber) {
                self.context.overrideSigningCertificate = customCert
            }
        } else if let installedApp = self.context.installedApp, let serialNumber = installedApp.certificateSerialNumber {
            debugLog("[UpdateAppCertificateOperation] InstalledApp '\(installedApp.name)' has custom certificate serial: '\(serialNumber)'")
            if let customCert = CertificateManager.shared.getSignableCertificate(for: serialNumber) {
                debugLog("[UpdateAppCertificateOperation] Loaded custom certificate '\(customCert.serialNumber)' for app '\(installedApp.name)'. Setting context.overrideSigningCertificate.")
                self.context.overrideSigningCertificate = customCert
            } else {
                debugLog("[UpdateAppCertificateOperation] WARNING: Signable certificate with serial '\(serialNumber)' not found for app '\(installedApp.name)'.")
            }
        }
        
        self.setProgress(100)
    }
}

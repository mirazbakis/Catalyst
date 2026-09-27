//
//  FileManager+SharedDirectories.swift
//  AltStore
//
//  Created by Riley Testut on 5/14/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

public extension FileManager
{
    var altstoreSharedDirectory: URL? {
        #if os(tvOS)
        return self.cachesDirectory
        #else
        if let appGroup = Bundle.main.altstoreAppGroup,
           let sharedDirectoryURL = self.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        {
            return sharedDirectoryURL
        }
        
        // Catalyst: Enterprise / Ad Hoc signing tools (and many enterprise profiles) strip the
        // App Group entitlement. Instead of refusing to start, keep Catalyst's data in a private
        // container. Widgets and SideBackup can't see it, but the app itself works normally.
        return self.privateSharedFallbackDirectory
        #endif
    }
    
    /// `true` when Catalyst runs without its App Group (e.g. installed with an enterprise certificate).
    var isUsingPrivateSharedFallback: Bool {
        #if os(tvOS)
        return false
        #else
        guard let appGroup = Bundle.main.altstoreAppGroup else { return true }
        return self.containerURL(forSecurityApplicationGroupIdentifier: appGroup) == nil
        #endif
    }
    
    private var privateSharedFallbackDirectory: URL? {
        guard let appSupport = self.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let url = appSupport.appendingPathComponent("PrivateSharedContainer", isDirectory: true)
        try? self.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }
    
    var appBackupsDirectory: URL? {
        let appBackupsDirectory = self.altstoreSharedDirectory?.appendingPathComponent("Backups", isDirectory: true)
        return appBackupsDirectory
    }
    
    func backupDirectoryURL(forBundleIdentifier bundleIdentifier: String) -> URL?
    {
        let backupDirectoryURL = self.appBackupsDirectory?.appendingPathComponent(bundleIdentifier, isDirectory: true)
        return backupDirectoryURL
    }
    
    func deleteBackup(forBundleIdentifier bundleIdentifier: String) throws
    {
        debugLog("[FileManager] deleteBackup() started for \(bundleIdentifier)")
        defer { debugLog("[FileManager] deleteBackup() completed for \(bundleIdentifier)") }
        
        guard let backupDirectoryURL = self.backupDirectoryURL(forBundleIdentifier: bundleIdentifier) else {
            debugLog("[FileManager] deleteBackup: Failed to construct backup directory URL for \(bundleIdentifier)")
            return
        }
        
        guard self.fileExists(atPath: backupDirectoryURL.path) else {
            debugLog("[FileManager] deleteBackup: No backup directory exists at \(backupDirectoryURL.path)")
            return
        }
        
        try self.removeItem(at: backupDirectoryURL)
        debugLog("[FileManager] Successfully deleted backup directory for \(bundleIdentifier) at \(backupDirectoryURL.path)")
    }
}

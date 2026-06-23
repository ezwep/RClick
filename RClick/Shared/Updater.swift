//
//  Updater.swift
//  RClick
//
//  Created by Li Xu on 2025/9/21.
//

import Foundation
import SwiftUI

// MARK: - Data Models

struct GitHubRelease: Codable, Identifiable {
    let id: Int
    let tagName: String
    let name: String
    let body: String
    let draft: Bool
    let prerelease: Bool
    let publishedAt: Date
    let assets: [Asset]
    let htmlUrl: String
    
    var version: String {
        tagName.replacingOccurrences(of: "v", with: "")
    }
    
    struct Asset: Codable {
        let id: Int
        let name: String
        let browserDownloadUrl: String
        let size: Int
        let contentType: String?
        
        enum CodingKeys: String, CodingKey {
            case id, name, size
            case browserDownloadUrl = "browser_download_url"
            case contentType = "content_type"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case name, body, draft, prerelease, assets
        case publishedAt = "published_at"
        case htmlUrl = "html_url"
    }
}

// MARK: - User Preferences

class UpdatePreferences: ObservableObject {
    @AppStorage("ignoredVersion") private var ignoredVersionData: Data = .init()
    
    // Get the list of ignored versions
    var ignoredVersions: [String] {
        get {
            do {
                return try JSONDecoder().decode([String].self, from: ignoredVersionData)
            } catch {
                return []
            }
        }
        set {
            do {
                ignoredVersionData = try JSONEncoder().encode(newValue)
            } catch {
                print("Failed to save ignored versions: \(error)")
            }
        }
    }
    
    // Ignore a specific version
    func ignoreVersion(_ version: String) {
        var ignored = ignoredVersions
        if !ignored.contains(version) {
            ignored.append(version)
            ignoredVersions = ignored
        }
    }
    
    // Check whether a version is ignored
    func isVersionIgnored(_ version: String) -> Bool {
        ignoredVersions.contains(version)
    }
}

// MARK: - GitHub API Service

class GitHubReleaseChecker {
    private let owner: String
    private let repo: String
    
    init(owner: String, repo: String) {
        self.owner = owner
        self.repo = repo
    }
    
    // Fetch the latest release
    func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        print(url)
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GitHubRelease.self, from: data)
    }
    
    // Check whether an update is needed
    func checkForUpdate(currentVersion: String, includePrereleases: Bool = false) async -> GitHubRelease? {
        print(currentVersion)
        do {
            let latestRelease = try await fetchLatestRelease()
            
            // Skip drafts and prereleases (unless explicitly included)
            if latestRelease.draft || (!includePrereleases && latestRelease.prerelease) {
                return nil
            }

            // Compare versions
            if compareVersions(currentVersion, latestRelease.version) == .orderedAscending {
                return latestRelease
            } else {
                print("the last verison \(latestRelease.version)")
            }
        } catch {
            print("Failed to check for updates: \(error)")
        }
        
        return nil
    }
    
    // Semantic version comparison
    private func compareVersions(_ version1: String, _ version2: String) -> ComparisonResult {
        let components1 = version1.components(separatedBy: ".")
        let components2 = version2.components(separatedBy: ".")
        
        for i in 0 ..< max(components1.count, components2.count) {
            let part1 = i < components1.count ? components1[i] : "0"
            let part2 = i < components2.count ? components2[i] : "0"
            
            if let num1 = Int(part1), let num2 = Int(part2) {
                if num1 < num2 { return .orderedAscending }
                if num1 > num2 { return .orderedDescending }
            } else {
                // Handle non-numeric parts (such as beta, rc, etc.)
                let comparison = part1.compare(part2)
                if comparison != .orderedSame {
                    return comparison
                }
            }
        }
        
        return .orderedSame
    }
}

// MARK: - Update Manager

@MainActor
class UpdateManager: ObservableObject {
    @Published var availableUpdate: GitHubRelease?
    @Published var isChecking = false
    @Published var updateError: String?
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var showUpdateSheet = false
    
    private let githubChecker: GitHubReleaseChecker
    private let preferences: UpdatePreferences
    private let currentVersion: String
    
    init(owner: String, repo: String, currentVersion: String) {
        self.githubChecker = GitHubReleaseChecker(owner: owner, repo: repo)
        self.preferences = UpdatePreferences()
        self.currentVersion = currentVersion
    }
    
    // Dismiss the update prompt
    func dismissUpdateSheet() {
        showUpdateSheet = false
        availableUpdate = nil
        updateError = nil
    }
      
    // Check for updates
    func checkForUpdates(force: Bool = false) async {
        isChecking = true
        updateError = nil
        showUpdateSheet = true
        
        defer { isChecking = false }
        
        guard let release = await githubChecker.checkForUpdate(currentVersion: currentVersion) else {
            print("not release")
            updateError = "You are already on the latest version"
            return
        }

        // Check whether the user has ignored this version
        if !force && preferences.isVersionIgnored(release.version) {
            print("Ignoring this version")
            updateError = "Ignored version \(release.version)"
            return
        }
            
        availableUpdate = release
    }
    
    // MARK: - Download and Install Methods

    func downloadAndInstallUpdate() async {
        print("start downloadAndInstallUpdate")
        guard let release = availableUpdate else {
            updateError = "No update available"
            print("No update available")
            return
        }

        // Find the .app.zip asset
        guard let appZipAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".app.zip") }) else {
            updateError = "No application package in .app.zip format was found"
            print("No update available")
            return
        }
        
        isDownloading = true
        downloadProgress = 0
        
        do {
            // 1. Download the ZIP file
            let downloadedURL = try await downloadAsset(asset: appZipAsset)

            // 2. Extract to a temporary directory
            let appURL = try await extractAppZip(zipURL: downloadedURL)

            // 3. Install the app into the Applications directory
            try await installApplication(appURL: appURL)

            // 4. Clean up temporary files
            try? FileManager.default.removeItem(at: downloadedURL)
            try? FileManager.default.removeItem(at: appURL.deletingLastPathComponent())

            // 5. Notify the user that installation is complete
            showInstallationCompleteAlert()

        } catch {
            updateError = "Installation failed: \(error.localizedDescription)"
        }
        
        isDownloading = false
    }

    func downloadAsset(asset: GitHubRelease.Asset) async throws -> URL {
        print("start downloadAsset:\(asset.browserDownloadUrl)")
        let tempDir = FileManager.default.temporaryDirectory
        let downloadURL = tempDir.appendingPathComponent(asset.name)
        
        var request = URLRequest(url: URL(string: asset.browserDownloadUrl)!)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        
        // Use AsyncThrowingStream to wrap the download progress and result
        return try await withCheckedThrowingContinuation { continuation in
            // Stream bytes and write to destination file
            let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
            let task = session.downloadTask(with: request) { tempURL, response, error in

                print("start do")
                if let error = error {
                    print("downn error")
                    continuation.resume(throwing: error)
                    return
                }

                guard let tempURL = tempURL,
                      let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200
                else {
                    continuation.resume(throwing: DownloadError.downloadFailed("Download failed"))
                    print("downn error")
                    return
                }

                do {
                    // Move the file to the destination location
                    try? FileManager.default.removeItem(at: downloadURL)
                    try FileManager.default.moveItem(at: tempURL, to: downloadURL)
                    print("download url: \(downloadURL.path)")
                    continuation.resume(returning: downloadURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            task.resume()
        }
    }

    // Associated object key
    private var DownloadDelegateKey: UInt8 = 0

    // MARK: - Extract APP Zip File

    private func extractAppZip(zipURL: URL) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let extractionDir = tempDir.appendingPathComponent("app_extraction")
        
        // Create the extraction directory
        try FileManager.default.createDirectory(at: extractionDir, withIntermediateDirectories: true)

        // Use a system command to extract
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipURL.path, "-d", extractionDir.path]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw InstallationError.zipExtractionFailed("Extraction failed: \(errorString)")
        }

        // Find the extracted .app file
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(at: extractionDir, includingPropertiesForKeys: nil)
        
        guard let appURL = contents.first(where: { $0.pathExtension == "app" }) else {
            throw InstallationError.noAppFound("No .app application was found in the ZIP file")
        }
        
        return appURL
    }

    // MARK: - Request Folder Access
    @MainActor
    private func requestApplicationsFolderAccess() async throws {
        let openPanel = NSOpenPanel()
        openPanel.message = "RClick needs permission to install the update into your Applications folder."
        openPanel.prompt = "Grant Permission"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.directoryURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first

        let response = await openPanel.begin()
        
        guard response == .OK, let selectedURL = openPanel.url else {
            throw InstallationError.permissionDenied("The user cancelled the authorization.")
        }

        // Verify that the user selected the correct folder
        let applicationsURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first!
        guard selectedURL.path == applicationsURL.path else {
            throw InstallationError.permissionDenied("Please select the correct 'Applications' folder.")
        }
    }
    // MARK: - Install App into the Applications Directory
    private func installApplication(appURL: URL) async throws {
        let fileManager = FileManager.default
        let applicationsURL = fileManager.urls(for: .applicationDirectory, in: .localDomainMask).first!
        let destinationAppURL = applicationsURL.appendingPathComponent(appURL.lastPathComponent)
        print("start install \(appURL.path) --- \(destinationAppURL.path)")
        // Before installing, check whether destinationAppURL is readable/writable; if not, request permission
         // Check write permission for the Applications folder
        if !fileManager.isWritableFile(atPath: applicationsURL.path) {
            print("No write permission for the Applications folder, requesting permission...")
            try await requestApplicationsFolderAccess()
        }
        do {
            // Check whether an app already exists at the destination
            if fileManager.fileExists(atPath: destinationAppURL.path) {
                // Try moving it to the Trash first instead of deleting directly
                try fileManager.trashItem(at: destinationAppURL, resultingItemURL: nil)
            }

            // Copy the app into the Applications directory
            try fileManager.copyItem(at: appURL, to: destinationAppURL)

            // Verify that the application is valid
            guard Bundle(url: destinationAppURL) != nil else {
//                try fileManager.removeItem(at: destinationAppURL)
                throw InstallationError.invalidAppBundle("The application bundle is invalid or corrupted")
            }
        } catch {
            print("❌ Installation failed: \(error)")
        }
        
    }

    // MARK: - Show Installation Complete Prompt

    private func showInstallationCompleteAlert() {
        let alert = NSAlert()
        alert.messageText = "Update Installation Complete"
        alert.informativeText = "The application was updated successfully. The app needs to be restarted to complete the update process."
        alert.addButton(withTitle: "Restart Now")
        alert.addButton(withTitle: "Restart Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Launch the new app and quit the current app
            launchNewApplicationAndExit()
        }
    }

    // MARK: - Launch New App and Quit

    private func launchNewApplicationAndExit() {
        let fileManager = FileManager.default
        let applicationsURL = fileManager.urls(for: .applicationDirectory, in: .localDomainMask).first!
        let currentAppName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "RClick"
        let newAppURL = applicationsURL.appendingPathComponent("\(currentAppName).app")
        
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: newAppURL, configuration: configuration) { _, error in
            if error != nil {
                print("Failed to launch the new app; it may need to be launched manually")
            }
            // Quit the current app regardless
            NSApp.terminate(nil)
        }
    }

    // Ignore the currently available update
    func ignoreCurrentUpdate() {
        if let version = availableUpdate?.version {
            preferences.ignoreVersion(version)
            availableUpdate = nil
        }
    }
    
    // Open the GitHub releases page
    func openReleasesPage() {
        if let url = URL(string: "https://github.com/wflixu/RClick/releases") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Error Types

    enum DownloadError: LocalizedError {
        case downloadFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .downloadFailed(let message):
                return message
            }
        }
    }

    enum InstallationError: LocalizedError {
        case zipExtractionFailed(String)
        case noAppFound(String)
        case invalidAppBundle(String)
        case permissionDenied(String)
        
        var errorDescription: String? {
            switch self {
            case .zipExtractionFailed(let message):
                return message
            case .noAppFound(let message):
                return message
            case .invalidAppBundle(let message):
                return message
            case .permissionDenied(let message):
                return message
            }
        }
    }
}

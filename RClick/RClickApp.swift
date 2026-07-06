//
//  RClickApp.swift
//  RClick
//
//  Created by Li Xu on 2024/4/4.
//
import AppKit
import Foundation
import SwiftUI
import SwiftData

import FinderSync
import os.log

@main
struct RClickApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(Key.showMenuBarExtra, store: .group) private var showMenuBarExtra = true

    @Environment(\.openWindow) var openWindow

    @AppLog(category: "main")
    private var logger
    let messager = Messager.shared

    @StateObject var appState = AppState.shared

    @StateObject private var updateManager = UpdateManager(
        owner: "wflixu",
        repo: "RClick",
        currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    )

    var body: some Scene {
        SettingsWindow(appState: appState, onAppear: {})
            .defaultAppStorage(.group)
            .environmentObject(updateManager)
            .modelContainer(SharedDataManager.sharedModelContainer)

        // Show the menu bar item when showMenuBarExtra is true
        MenuBarExtra(
            "RClick", image: "MenuBar", isInserted: $showMenuBarExtra
        ) {
            MenuBarView()
        }.defaultAppStorage(.group)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    @AppLog(category: "AppDelegate")
    private var logger

    var appState: AppState = .shared
    var pluginRunning: Bool = false
    var heartBeatCount = 0

    let messager = Messager.shared
    var showMenuBarExtra = UserDefaults.group.bool(forKey: Key.showMenuBarExtra)
    var showInDock = UserDefaults.group.bool(forKey: Key.showInDock)
    var settingsWindow: NSWindow!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Function executed after the app launches

        if showInDock {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }

        messager.on(name: Key.messageFromFinder) { payload in

            self.logger.info("recive mess from finder by app \(payload.description)")
            switch payload.action {
            case "open":
                self.openApp(rid: payload.rid, target: payload.target)
            case "actioning":
                self.actionHandler(rid: payload.rid, target: payload.target, trigger: payload.trigger)
            case "Create File":
                self.createFile(rid: payload.rid, target: payload.target)
            case "common-dirs":
                self.openCommonDirs(target: payload.target)
            case "heartbeat":
                self.logger.warning("message from finder plugin heartbeat")
                self.pluginRunning = true
            default:
                self.logger.warning("actioning payload no matched")
            }
        }
        sendObserveDirMessage()
        
    }
    
    func openCommonDirs(target: [String]) {
        logger.info("Started opening frequently used directories, target paths: \(target)")

        for dirPath in target {
            let path = dirPath.removingPercentEncoding ?? dirPath
            let url = URL(fileURLWithPath: path, isDirectory: true)

            logger.info("Opening directory: \(path)")
            NSWorkspace.shared.open(url)
        }

        logger.info("Finished opening frequently used directories")
    }

    func sendObserveDirMessage() {
        // Send the decoded filesystem path (not percent-encoded) so the
        // extension's URL(fileURLWithPath:) reconstructs the real directory.
        // Paths with spaces (e.g. "Claude Code") would otherwise become
        // "Claude%20Code" and match no real folder, leaving the menu empty.
        let target: [String] = appState.dirs.map { $0.url.path(percentEncoded: false) }

        messager.sendMessage(name: "running", data: MessagePayload(action: "running", target: target))
        if !pluginRunning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.sendObserveDirMessage()
            }
        }
    }

    // Build a new, non-existing file name within the current folder
    func getUniqueFilePath(dir: String, ext: String) -> String {
        // Create the file manager
        let fileManager = FileManager.default

        // Base file name
        let baseFileName = String(localized: "Untitled")

        // Initial file path
        var filePath = "\(dir)\(baseFileName)\(ext)"

        // File counter
        var counter = 1

        // Check whether the file exists until a non-existing path is found
        while fileManager.fileExists(atPath: filePath) {
            // Update the file name and path, incrementing the counter
            let newFileName = "\(baseFileName)\(counter)"
            filePath = "\(dir)\(newFileName)\(ext)"
            counter += 1
        }

        return filePath
    }

    func actionHandler(rid: String, target: [String], trigger: String) {
        guard let rcitem = appState.getActionItem(rid: rid) else {
            logger.warning("when createFile,but not have fileType ")
            return
        }

        switch rcitem.id {
        case "copy-path":
            copyPath(target)
        case "delete-direct":
            deleteFoldorFile(target, trigger)
        case "unhide":
            unhideFilesAndDirs(target, trigger)
        case "hide":
            hideFilesAndDirs(target, trigger)
        case "airdrop":
            showAirDrop(target, trigger)
        default:
            logger.warning("no action id matched")
        }
    }

    func showAirDrop(_ target: [String], _ trigger: String) {
        logger.info("---- showAirDrop  trigger:\(trigger)")
        let fm = FileManager.default
        var fileURLs: [URL] = []

        if trigger == "ctx-container" {
            // Show a warning dialog
            let alert = NSAlert()
            alert.messageText = "Warning"
            alert.informativeText = "Cannot share the current folder. Please select a file or subfolder to share."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        for item in target {
            let decodedPath = item.removingPercentEncoding ?? item
            logger.info("airdrop path \(decodedPath)")

            if Utils.isProtectedFolder(decodedPath) {
                // Show a warning dialog
                let alert = NSAlert()
                alert.messageText = "Warning"
                alert.informativeText = "Cannot share a protected system folder: \(decodedPath)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()

                logger.warning("Attempted to share a protected system folder, operation blocked: \(decodedPath)")
                continue
            }

            var isDir: ObjCBool = false
            if fm.fileExists(atPath: decodedPath, isDirectory: &isDir) {
                if isDir.boolValue {
                    logger.warning("Cannot share a folder via AirDrop: \(decodedPath)")
                    let alert = NSAlert()
                    alert.messageText = "Notice"
                    alert.informativeText = "Cannot share a folder via AirDrop: \(decodedPath)"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                    continue
                } else {
                    fileURLs.append(URL(fileURLWithPath: decodedPath))
                }
            }
        }

        if !fileURLs.isEmpty {
            if let airDropService = NSSharingService(named: .sendViaAirDrop) {
                airDropService.perform(withItems: fileURLs)
                logger.info("Shared files via AirDrop: \(fileURLs.map { $0.path }.joined(separator: ", "))")
            } else {
                logger.warning("Unable to obtain the AirDrop service")
            }
        }
    }

    // Reveal all hidden files and folders within the target folder
    func unhideFilesAndDirs(_ target: [String], _ trigger: String) {
        logger.info("Started unhiding files and directories, target paths: \(target)")
        if let dirPath = target.first {
            let fileManager = FileManager.default
            let path = dirPath.removingPercentEncoding ?? dirPath
            logger.info("Processing main directory: \(path)")
            var url = URL(fileURLWithPath: path)

            // Only process the contents one level below the directory
            do {
                let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isHiddenKey], options: [.skipsPackageDescendants])
                for case var fileURL in contents {
                    do {
                        var resourceValues = URLResourceValues()
                        resourceValues.isHidden = false
                        try fileURL.setResourceValues(resourceValues)
                        logger.info("Successfully unhid: \(fileURL.path)")
                    } catch {
                        logger.error("Failed to unhide: \(fileURL.path): \(error)")
                    }
                }
            } catch {
                logger.error("Failed to get directory contents: \(error)")
            }

            // Process the directory itself
            do {
                var resourceValues = URLResourceValues()
                resourceValues.isHidden = false
                try url.setResourceValues(resourceValues)
                logger.info("Successfully unhid the main directory: \(path)")
            } catch {
                logger.error("Failed to unhide the main directory: \(path): \(error)")
            }
            logger.info("Finished unhiding, directory processed: \(path)")
        }
    }

    // Hide the target file or folder
    func hideFilesAndDirs(_ target: [String], _ trigger: String) {
        logger.info("Started hiding files and directories, target paths: \(target), trigger: \(trigger)")
        let fileManager = FileManager.default

        if trigger == "ctx-container", let dirPath = target.first {
            let path = dirPath.removingPercentEncoding ?? dirPath
            logger.info("Processing main directory: \(path)")
            let url = URL(fileURLWithPath: path)

            // Only process the contents one level below the directory
            do {
                let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsPackageDescendants])
                for case var fileURL in contents {
                    // Skip if it is a protected file path
                    if Utils.isProtectedFolder(fileURL.path) {
                        logger.warning("Skipping protected file path: \(fileURL.path)")
                        continue
                    }
                    do {
                        var resourceValues = URLResourceValues()
                        resourceValues.isHidden = true
                        try fileURL.setResourceValues(resourceValues)
                        logger.info("Successfully hid: \(fileURL.path)")
                    } catch {
                        logger.error("Failed to hide: \(fileURL.path): \(error)")
                    }
                }
            } catch {
                logger.error("Failed to get directory contents: \(error)")
            }
        } else if trigger == "ctx-items" {
            for dirPath in target {
                let path = dirPath.removingPercentEncoding ?? dirPath
                logger.info("Processing path: \(path)")
                var url = URL(fileURLWithPath: path)

                // Process a single file or directory
                if Utils.isProtectedFolder(path) {
                    logger.warning("Skipping protected file path: \(path)")
                    continue
                }
                do {
                    var resourceValues = URLResourceValues()
                    resourceValues.isHidden = true
                    try url.setResourceValues(resourceValues)
                    logger.info("Successfully hid: \(path)")
                } catch {
                    logger.error("Failed to hide: \(path): \(error)")
                }
            }
        }
        logger.info("Finished hiding operation")
    }

    func copyPath(_ target: [String]) {
        if let dirPath = target.first {
            let pasteboard = NSPasteboard.general
            // must do to fix bug
            pasteboard.clearContents()

            pasteboard.setString(dirPath.removingPercentEncoding ?? dirPath, forType: .string)
        }
    }

    func deleteFoldorFile(_ target: [String], _ trigger: String) {
        logger.info("---- deleteFoldorFile  trigger:\(trigger)")
        let fm = FileManager.default
        // If it is a container, it cannot be deleted
        if trigger == "ctx-container" {
            // Show a warning dialog
            let alert = NSAlert()
            alert.messageText = "Warning"
            alert.informativeText = "Cannot delete the current folder. Please select a file or subfolder to delete."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        for item in target {
            let decodedPath = item.removingPercentEncoding ?? item

            if Utils.isProtectedFolder(decodedPath) {
                // Show a warning dialog
                let alert = NSAlert()
                alert.messageText = "Warning"
                alert.informativeText = "Cannot delete a protected system folder: \(decodedPath)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()

                logger.warning("Attempted to delete a protected system folder, operation blocked: \(decodedPath)")
                continue
            }

            if let permDir = appState.dirs.first(where: { permd in
                item.contains(permd.url.path())
            }) {
                var isStale = false
                do {
                    let folderURL = try URL(resolvingBookmarkData: permDir.bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)

                    if isStale {
                        // Recreate the bookmarkData
                        // createBookmark(for: folderURL) // The earlier function can be called here
                    }

                    // Enter the security scope
                    let success = folderURL.startAccessingSecurityScopedResource()
                    if success {
                        try fm.removeItem(atPath: item.removingPercentEncoding ?? item)
                        // Release the resource when done
                        folderURL.stopAccessingSecurityScopedResource()
                    } else {
                        logger.warning("fail access scope \(permDir.url.path)")
                    }
                } catch {
                    logger.error("delete \(target) file run error \(error)")
                }
            }
        }
    }

    func createFile(rid: String, target: [String]) {
        guard let rcitem = appState.getFileType(rid: rid), let dirPath = target.first else {
            logger.warning("when createFile,but not have fileType \(rid) ")
            return
        }

        let ext = rcitem.ext
        logger.info("create file dir:\(dirPath) -- ext \(ext)")
        // Full file path
        let filePath = getUniqueFilePath(dir: dirPath.removingPercentEncoding ?? dirPath, ext: ext)

        let fileURL = URL(fileURLWithPath: filePath)

        if let dir = appState.dirs.first(where: {
            dirPath.contains($0.url.path)
        }) {
            var isStale = false
            do {
                let folderURL = try URL(resolvingBookmarkData: dir.bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)

                // Enter the security scope
                let success = folderURL.startAccessingSecurityScopedResource()
                if success {
                    do {
                        let fileManager = FileManager.default

                        // Check whether there is a valid template URL
                        if let templateUrl = rcitem.template {
                            try fileManager.copyItem(at: templateUrl, to: fileURL)
                            logger.info("Successfully copied the template to the target path: \(fileURL.path)")

                        } else {
                            // Get the template file from the bundle
                            if let defaultTemplateURL = Bundle.main.url(forResource: "template", withExtension: ext.replacingOccurrences(of: ".", with: "")) {
                                logger.info("Creating file from template, template path: \(defaultTemplateURL.path)")
                                try fileManager.copyItem(at: defaultTemplateURL, to: fileURL)
                                logger.info("Successfully copied the template to the target path: \(fileURL.path)")
                            } else {
                                logger.warning("Template file does not exist: \(ext)")
                                // Create an empty file when the template does not exist
                                try Data().write(to: fileURL)
                            }
                        }
                    } catch let error as NSError {
                        switch error.domain {
                        case NSCocoaErrorDomain:
                            switch error.code {
                            case NSFileNoSuchFileError:
                                logger.error("File does not exist: \(filePath)")
                            case NSFileWriteOutOfSpaceError:
                                logger.error("Insufficient disk space")
                            case NSFileWriteNoPermissionError:
                                logger.error("No write permission: \(filePath)")
                            default:
                                logger.error("Error creating file: \(error.localizedDescription) (error code: \(error.code))")
                            }
                        default:
                            logger.error("Unhandled error: \(error.localizedDescription) (error code: \(error.code))")
                        }
                    }
                    // Release the resource when done
                    folderURL.stopAccessingSecurityScopedResource()
                } else {
                    logger.warning("fail access scope \(dir.url.path)")
                }
            } catch {
                print("Failed to resolve bookmark: \(error)")
            }
        }
    }

    func openApp(rid: String, target: [String]) {
        guard let rcitem = appState.getAppItem(rid: rid) else {
            logger.warning("when openapp,but not have app \(rid)")
            return
        }

        let appUrl = rcitem.url
        let config = NSWorkspace.OpenConfiguration()
        config.promptsUserIfNeeded = false

        for dirPath in target {
            let dir = URL(fileURLWithPath: dirPath.removingPercentEncoding ?? dirPath, isDirectory: true)

            config.arguments = rcitem.arguments
            config.environment = rcitem.environment

            if appUrl.path.hasSuffix("WezTerm.app") {
                // Create a Process instance
                let process = Process()

                // Set the path to the binary to run
                process.executableURL = URL(fileURLWithPath: "/Users/lixu/play/rpm/target/debug/rpm")

                // Set the command line arguments (if any)
                process.arguments = ["--name", "arg2"]

                // Set standard output and standard error
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    // Start the process
                    try process.run()

                    // Wait for the process to finish
                    process.waitUntilExit()

                    // Read the output
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8) {
                        print("Output: \(output)")
                    }
                } catch {
                    print("Error: \(error)")
                }
            } else {
                logger.info("starting open dir: \(dir.path), app: \(appUrl.path())")
                NSWorkspace.shared.open([dir], withApplicationAt: appUrl, configuration: config) { runningApp, error in
                    if let error = error {
                        self.logger.error("Error opening application: \(error.localizedDescription, privacy: .public)")
                    } else if let runningApp = runningApp {
                        self.logger.info("Successfully opened application: \(runningApp.localizedName ?? "Unknown")")
                    }
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        messager.sendMessage(name: "quit", data: MessagePayload(action: "quit", target: [], trigger: "unknown"))
        logger.info("applicationWillTerminate")
    }
}

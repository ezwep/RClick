//
//  File.swift
//  RClick
//
//  Created by Li Xu on 2024/9/26.
//

import Combine
import Foundation
import OrderedCollections
import SwiftUI

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    @AppLog(category: "AppState")
    private var logger
    
    @Published var apps: [OpenWithApp] = []
    @Published var dirs: [PermissiveDir] = []
    @Published var actions: [RCAction] = []
    @Published var newFiles: [NewFile] = []
    @Published var cdirs: [CommonDir] = []
    @Published var inExt: Bool
    
    @Published var showMenuBar: Bool = true;
    
    
    init(inExt: Bool = false) {
        self.inExt = inExt
        Task {
            await MainActor.run {
                logger.info("start load")
                try? load()
            }
        }
    }
    
    // Apps
    @MainActor func deleteApp(index: Int) {
        apps.remove(at: index)
        do {
            try save()
            // use result
        } catch {
            // handle error
            logger.info("save error: \(error.localizedDescription)")
        }
    }

    @MainActor func addApp(item: OpenWithApp) {
        logger.info("start add app")
        apps.append(item)
        
        do {
            try save()
            // use result
        } catch {
            // handle error
            logger.info("save error: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    func updateApp(id: String, itemName: String, arguments: [String], environment: [String: String]) {
        if let index = apps.firstIndex(where: { $0.id == id }) {
            var updatedApp = apps[index]
            updatedApp.itemName = itemName
            updatedApp.arguments = arguments
            updatedApp.environment = environment
            apps[index] = updatedApp
            try? save()
        }
    }
    
    func getAppItem(rid: String) -> OpenWithApp? {
        return apps.first { rid.contains($0.id) }
    }
    
    func getFileType(rid: String) -> NewFile? {
        return newFiles.first(where: { nf in
            rid == nf.id
        })
    }
    
    @MainActor func addNewFile(_ item: NewFile) {
        logger.info("start add new file type")
        newFiles.append(item)
        
        do {
            try save()
            // use result
        } catch {
            // handle error
            logger.info("save error: \(error.localizedDescription)")
        }
    }
    
    func getActionItem(rid: String) -> RCAction? {
        actions.first(where: { rcAtion in
            rcAtion.id == rid
        })
    }
    
    // Action
    @MainActor func toggleActionItem() {
        try? save()
    }

    @MainActor func resetActionItems() {
        actions = RCAction.all
        try? save()
    }
    
    @MainActor func resetFiletypeItems() {
        newFiles = NewFile.all
        try? save()
    }
    
    // Permission
    @MainActor func deletePermissiveDir(index: Int) {
        dirs.remove(at: index)

        try? save()
    }

    @MainActor func hasParentBookmark(of url: URL) -> Bool {
        return false
//        let storedUrls = dirs.map { $0.url }
//        for storedURL in storedUrls {
//            // Ensure storedURL is a directory and the passed-in URL is prefixed by storedURL's path
//            if url.path.hasPrefix(storedURL.path) {
//                return true
//            }
//        }
//        return false
    }
    
    @MainActor
    private func save() throws {
        let encoder = PropertyListEncoder()
        let appItemsData = try encoder.encode(OrderedSet(apps))
        let actionItemsData = try encoder.encode(OrderedSet(actions))
        let filetypeItemsData = try encoder.encode(OrderedSet(newFiles))
        let permDirsData = try encoder.encode(OrderedSet(dirs))
        let commonDirsData = try encoder.encode(OrderedSet(cdirs))
        UserDefaults.group.set(appItemsData, forKey: Key.apps)
        UserDefaults.group.set(actionItemsData, forKey: Key.actions)
        UserDefaults.group.set(filetypeItemsData, forKey: Key.fileTypes)
        UserDefaults.group.set(permDirsData, forKey: Key.permDirs)
        UserDefaults.group.set(commonDirsData, forKey: Key.commonDirs)
    }
    
    @MainActor
    func savePermissiveDir() throws {
        let encoder = PropertyListEncoder()
        let permDirsData = try encoder.encode(OrderedSet(dirs))
        UserDefaults.group.set(permDirsData, forKey: Key.permDirs)
    }

    //  Save frequently used folders
    @MainActor
    func saveCommonDir() throws {
        let encoder = PropertyListEncoder()
        let commonDirsData = try encoder.encode(OrderedSet(cdirs))
        UserDefaults.group.set(commonDirsData, forKey: Key.commonDirs)
        logger.info("save common dirs success")
    }
    
    @MainActor func refresh() {
        _ = try? load()
    }
    
    @MainActor func sync() {
        _ = try? save()
    }
    
    @MainActor
    private func load() throws {
        let decoder = PropertyListDecoder()
        if !inExt {
            if let permDirsData = UserDefaults.group.data(forKey: Key.permDirs) {
                dirs = try decoder.decode([PermissiveDir].self, from: permDirsData)
                logger.info("load permDir success")
                
                for dir in dirs {
                    var isStale = false
                    do {
                        let folderURL = try URL(resolvingBookmarkData: dir.bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)

                        if isStale {
                            // Re-create bookmarkData
                            // createBookmark(for: folderURL) // the previous function can be called here
                        }

                        // Enter the security scope
                        let success = folderURL.startAccessingSecurityScopedResource()
                        if success {
                            // Release the resource when done
                            logger.info("startAccessingSecurityScopedResource success")
//                            folderURL.stopAccessingSecurityScopedResource()
                        } else {
                            logger.warning("fail access scope \(dir.url.path)")
                        }
                    } catch {
                        print("Failed to resolve bookmark: \(error)")
                    }
                }
                 
            } else {
                logger.warning("load permission dirfailed")
               
                dirs = []
            }
        }

        if let commonDirsData = UserDefaults.group.data(forKey: Key.commonDirs) {
            cdirs = try decoder.decode([CommonDir].self, from: commonDirsData)
                
            logger.info("load common dirs success")
        } else {
            logger.warning("load common dirs failed")
            cdirs = []
        }
        
        if let actionData = UserDefaults.group.data(forKey: Key.actions) {
            actions = try decoder.decode([RCAction].self, from: actionData)
            logger.info("load actions success")
        } else {
            logger.warning("load actions failed")
            actions = RCAction.all
        }
        
        if let filetypeItemData = UserDefaults.group.data(forKey: Key.fileTypes) {
            newFiles = try decoder.decode([NewFile].self, from: filetypeItemData)
            logger.info("load filetype success")
        } else {
            logger.warning("load  new file type failed")
            newFiles = NewFile.all
        }
        
        if let appItemData = UserDefaults.group.data(forKey: Key.apps) {
            apps = try decoder.decode([OpenWithApp].self, from: appItemData)
            logger.info("load apps success")
        } else {
            logger.warning("load apps failed")
            apps = OpenWithApp.defaultApps
        }
    }
}

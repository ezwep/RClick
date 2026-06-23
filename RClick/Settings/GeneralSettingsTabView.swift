//
//  GeneralSettingsTabView.swift
//  RClick
//
//  Created by Li Xu on 2024/4/10.
//

import AppKit
import Cocoa
import FinderSync
import SwiftUI

struct GeneralSettingsTabView: View {
    @AppLog(category: "settings-general")
    private var logger

    @AppStorage("extensionEnabled") private var extensionEnabled = false
    @AppStorage(Key.showMenuBarExtra) private var showMenuBarExtra = true
    @AppStorage(Key.showInDock) private var showInDock = false

    @EnvironmentObject var store: AppState

    @State private var showAlert = false
    @State private var wrongFold = false

    @State private var showDirImporter = false

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    let messager = Messager.shared

    var enableIcon: String {
        if extensionEnabled {
            return "checkmark.circle.fill"
        } else {
            return "checkmark.circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                Text("Enable extension").font(.title3).fontWeight(.semibold)
                Spacer()
                Button(action: openExtensionset) {
                    Label("Open Settings", systemImage: enableIcon)
                }
            }

            Text("The RClick extension needs to be enabled for it to work properly")
                .font(.headline)
                .fontWeight(.thin)
                .foregroundColor(Color.gray)
            Divider()

            HStack {
                LaunchAtLogin.Toggle(
                    LocalizedStringKey("Launch at login")
                )
            }
            Divider()
            Text("App Icon Show").font(.title2)

            HStack {
                Toggle("Show in menu bar", isOn: $showMenuBarExtra)
                    .toggleStyle(.checkbox)
                Spacer()
                // Toggle for showMenuBarExtra
                Toggle("Show in dock", isOn: $showInDock)
                    .toggleStyle(.checkbox)
                    .onChange(of: showInDock) { _, newValue in
                        logger.debug("the hcnage --- a kjd \(newValue)")
                        // Handle the toggle state change here
                        if newValue {
                            // Show the menu bar icon
                            NSApp.setActivationPolicy(.regular)
                        } else {
                            // Hide the menu bar icon
                            NSApp.setActivationPolicy(.accessory)
                        }
                    }
            }
            // Toggle for showMenuBarExtra

            Divider()
            HStack {}.frame(height: 10)

            VStack(alignment: .leading) {
                Section {
                    List {
                        ForEach(store.dirs) { item in
                            HStack {
                                Image(systemName: "folder")
                                Text(verbatim: item.url.path)
                                Spacer()
                                Button {
                                    removeBookmark(item)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Authorization folder").font(.title3).fontWeight(.semibold)
                        Spacer()
                        Button {
                            showDirImporter = true
                        } label: { Label("Add", systemImage: "folder.badge.plus") }
                    }

                } footer: {
                    VStack {
                        HStack {
                            Text("The operation of the menu can only be executed in authorized folders")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Spacer()
                        }
                    }
                }
            }
            .alert(
                Text("Invalid Folder Selection"),
                isPresented: $wrongFold
            ) {
                Button("OK") {
                    showDirImporter = true
                }
            } message: {
                Text("The selected folder is a subdirectory of the previously chosen folder. Please select a different folder.")
            }
        }
        .alert(
            Text("Not Authorized Folder"),
            isPresented: $showAlert
        ) {
            Button("OK") {
                showDirImporter = true
            }
        } message: {
            Text("You must grant access to the folder to use this feature.")
        }
        .fileImporter(
            isPresented: $showDirImporter,
            allowedContentTypes: [.directory],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(dirs):
                startAddDir(dirs.first!)

            case let .failure(error):
                // handle error
                print(error)
            }
        }

        .onAppear {
            extensionEnabled = FIFinderSyncController.isExtensionEnabled

        }.onForeground {
            updateEnableState()
//            Task {
//                await checkPermissionFolder()
//            }
        }
        .task {
//            await checkPermissionFolder()
        }
    }

    func updateEnableState() {
        extensionEnabled = FIFinderSyncController.isExtensionEnabled
    }

    func checkPermissionFolder() async {
        let isEmpty = store.dirs.isEmpty
        if isEmpty {
            showAlert = true
        } else {
            logger.info("no empty")
        }
    }

    private func insertNewPermDir(url: URL) {
        // 2. Create a unique ID
        let newId = UUID().uuidString

        // 3. Create bookmark data (you need to provide this based on your actual situation)
        // For example, you can try to create bookmark data from the URL, or provide the corresponding data based on your app logic.
        // If there is no actual data for now, you can use an empty Data(), but this is not recommended long term.
        let bookmarkData: Data
        do {
            bookmarkData = try url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            print("Failed to create bookmark data: \(error)")
            // Decide on error handling based on your needs; here we use empty Data
            bookmarkData = Data()
        }

        // 4. Create a new PermDir instance
        let newPermDir = PermDir(id: newId, url: url, bookmark: bookmarkData)

        // 5. Insert into the model context
        modelContext.insert(newPermDir)

        // 6. Save the context (SwiftData sometimes saves automatically, but explicit saving is a good habit, especially after important operations)
        do {
            try modelContext.save()
            print("PermDir inserted successfully.")
        } catch {
            print("Failed to save context: \(error)")
        }
    }

    @MainActor
    func startAddDir(_ url: URL) {
        let hasParentDir = store.hasParentBookmark(of: url)
        if hasParentDir {
            wrongFold = true
//            showAlert = true
            logger.info("hasParentDir\(hasParentDir)")
        } else {
            store.dirs.append(PermissiveDir(permUrl: url))
            // Declare a PermDir entity and insert it into the modelContext
            insertNewPermDir(url: url)
            try? store.savePermissiveDir()

            let observeDirs = store.dirs.map { $0.url.path }
            messager.sendMessage(name: "running", data: MessagePayload(action: "running", target: observeDirs))
        }
    }

    @MainActor private func removeBookmark(_ item: PermissiveDir) {
        // Look up offsets based on item
        if let index = store.dirs.firstIndex(of: item) {
            store.deletePermissiveDir(index: index)
        }
    }

    private func openExtensionset() {
        FinderSync.FIFinderSyncController.showExtensionManagementInterface()
    }
}

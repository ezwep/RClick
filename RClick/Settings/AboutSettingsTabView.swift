//
//  AdvancedSettingsView.swift
//  RClick
//
//  Created by Li Xu on 2024/4/4.
//

import AppKit
import ExtensionFoundation
import ExtensionKit
import FinderSync
import SwiftUI

struct AboutSettingsTabView: View {
    let messager = Messager.shared
    @EnvironmentObject var updateManager: UpdateManager

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Image("Logo")
                    .resizable()
                    .frame(maxWidth: 128, maxHeight: 128)
                Spacer()
            }
            HStack {
                Spacer()
                Text("RClick").font(.title)
                Text("\(getAppVersion()) (\(getBuildVersion()))")
                Spacer()
            }
            HStack {
                Spacer()
                Text("RClick is a right-click menu extension that allows you to add applications for opening folders and includes some common actions!").font(.title3)
                Spacer()
            }
            Spacer()
            // Add a button that checks for updates when tapped
            VStack {
                // Check for updates button
                Button(action: {
                    Task {
                        await updateManager.checkForUpdates(force: true)
                    }
                }) {
                    if updateManager.isChecking {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Check for Updates")
                    }
                }
            }
            Spacer()
            Divider()
            HStack(alignment: .center) {
                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/wflixu/RClick")!)
                } label: {
                    Image("github")
                }

                Text(verbatim: "https://github.com/wflixu/RClick")
                Spacer()
            }
        }
    }

    func getAppVersion() -> String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "Unknown"
    }

    func getBuildVersion() -> String {
        if let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            return buildVersion
        }
        return "Unknown"
    }
}

#Preview {
    AboutSettingsTabView()
}

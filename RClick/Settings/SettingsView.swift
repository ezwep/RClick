//
//  SettingsView.swift
//  RClick
//
//  Created by Li Xu on 2024/4/4.
//

import SwiftUI

enum Tabs: String, CaseIterable, Identifiable {
    case general = "General"
    case apps = "Apps"
    case actions = "Actions"
    case newFile = "New File"
    case cdirs = "Common Dir"
    case about = "About"

    var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .general: "slider.horizontal.2.square"
        case .apps: "apps.ipad.landscape"
        case .actions: "bolt.square"
        case .newFile: "doc.badge.plus"
        case .cdirs: "folder.badge.gearshape"
        case .about: "exclamationmark.circle"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: Tabs = .general
    @EnvironmentObject var appState: AppState
    @State var showSelectApp = false

    @ViewBuilder
    private var sidebar: some View {
        Section {
            Divider()
            List(selection: self.$selectedTab) {
                ForEach(Tabs.allCases, id: \.self) { tab in
                    HStack {
                        // Use a fixed-size frame to keep the icon size consistent
                        Label {
                            Text(LocalizedStringKey(tab.rawValue))
                                .font(.title2)
                        } icon: {
                            Image(systemName: tab.icon)
                                .font(.title2)
                                .frame(width: 24, height: 24)
                        }
                        .padding(.all, 8)
                        .labelStyle(.titleAndIcon)
                        Spacer(minLength: 0)
                    }
                    .onTapGesture {
                        self.selectedTab = tab
                    }
                }
            }
            .listStyle(SidebarListStyle())
            .scrollDisabled(true)
            .navigationSplitViewColumnWidth(210)
        } header: {
            //  App Icon section
            VStack {
                HStack {
                    Spacer()
                    Image("Logo")
                        .resizable()
                        .frame(width: 64, height: 64)
                    Spacer()
                }
                HStack {
                    Spacer()
                    Text("RClick").font(.title)
                    Text("\(self.getAppVersion())")
                    Spacer()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 24)
        }
        .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
        .removeSidebarToggle()
    }

    @ViewBuilder var detailView: some View {
        // Right-side content
        Group {
            switch self.selectedTab {
            case .general:
                GeneralSettingsTabView()
            case .apps:
                AppsSettingsTabView()
            case .actions:
                ActionSettingsTabView()
            case .newFile:
                NewFileSettingsTabView()
            case .cdirs:
                CommonDirsSettingTabView()
            case .about:
                AboutSettingsTabView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 450,idealWidth: 600, maxWidth: 800)
        .padding()
    }

    var body: some View {
        NavigationSplitView {
            self.sidebar
        } detail: {
            self.detailView
        }
    }

    func getAppVersion() -> String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "Unknown"
    }
}

extension View {
    /// Removes the sidebar toggle button from the toolbar.
    func removeSidebarToggle() -> some View {
        toolbar(removing: .sidebarToggle)
            .toolbar {
                Color.clear
            }
    }
}

#Preview {
    SettingsView()
}

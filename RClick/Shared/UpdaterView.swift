//
//  Up.swift
//  RClick
//
//  Created by Li Xu on 2025/9/21.
//
import SwiftUI

struct UpdateView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var updateManager: UpdateManager
    
    var body: some View {
        VStack(spacing: 20) {
            if updateManager.isChecking {
                checkingView
            } else if let release = updateManager.availableUpdate {
                updateAvailableView(release)
            } else if let error = updateManager.updateError {
                errorView(error)
            } else {
                noUpdateView
            }
        }
        .padding(20)
        .frame(width: 400)
    }
    
    private var checkingView: some View {
        VStack(spacing: 15) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Checking for updates...")
                .font(.headline)
        }
    }
    
    private func updateAvailableView(_ release: GitHubRelease) -> some View {
        // The update-available view implementation stays unchanged...
        VStack(spacing: 15) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.blue)
            
            Text("New Version Available")
                .font(.title2)
                .bold()
            
            Text("Version \(release.version)")
                .font(.title3)
                .foregroundColor(.secondary)
            
            ScrollView {
                Text(release.body)
                    .font(.body)
                    .padding(5)
            }
            .frame(maxHeight: 150)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            
            HStack {
                Button("Ignore This Version") {
                    updateManager.ignoreCurrentUpdate()
                    updateManager.dismissUpdateSheet()
                }
                
                Button("Download Manually") {
                    updateManager.openReleasesPage()
                    updateManager.dismissUpdateSheet()
                }
                
                Button("Download and Install") {
                    Task {
                        await updateManager.downloadAndInstallUpdate()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private var noUpdateView: some View {
        VStack(spacing: 15) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.green)
            
            Text("Up to Date")
                .font(.title2)
                .bold()
            
            Text("You are on the latest version. No update is needed.")
                .foregroundColor(.secondary)
            
            Button("OK") {
                updateManager.dismissUpdateSheet()
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 15) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.yellow)
            
            Text("Failed to Check for Updates")
                .font(.title2)
                .bold()
            
            Text(error)
                .font(.body)
                .multilineTextAlignment(.center)
            
            Button("OK") {
                updateManager.dismissUpdateSheet()
            }
            .buttonStyle(.bordered)
        }
    }
}

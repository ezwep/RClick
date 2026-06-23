//
//  ModelContainer.swift
//  RClick
//
//  Created by Li Xu on 2025/10/3.
//

import Foundation
import SwiftData

// Shared ModelContainer configuration utility class
class SharedDataManager {
    static let appGroupIdentifier = Constants.suitName

    static var sharedModelContainer: ModelContainer = {
        do {
            // Get the App Group shared directory
            let storeURL: URL

            guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
                fatalError("Unable to get the App Group shared directory. Please check the App Group configuration: \(appGroupIdentifier)")
            }
            storeURL = containerURL.appendingPathComponent("RClickDatabase.sqlite")

            // Create the ModelConfiguration using the shared path
            let configuration = ModelConfiguration(
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )

            // Create the ModelContainer
            let container = try ModelContainer(
                for: PermDir.self, // your model types
                configurations: configuration
            )

            return container
        } catch {
            fatalError("Failed to create shared model container: \(error)")
        }
    }()
}

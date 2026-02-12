//
//  DataManager.swift
//  CloudKitSharing
//
//  Central SwiftData container with CloudKit sync enabled.
//
//  KEY DIFFERENCE from the SwiftDataSharing demo:
//  This container uses `cloudKitDatabase: .automatic` so SwiftData
//  automatically syncs the private database via CloudKit. Shared records
//  (via CKShare) are handled by SharingManager separately.
//

import Foundation
import SwiftData
import WidgetKit

/// Non-isolated constants accessible from any actor.
enum AppConstants {
    static let cloudKitContainerID = "iCloud.com.example.cloudkitsharing"
}

@MainActor
final class DataManager {
    static let shared = DataManager()

    let container: ModelContainer

    private init() {
        container = DataManager.createContainer()
    }

    private static func createContainer() -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)

        let config = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

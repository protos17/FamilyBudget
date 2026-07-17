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
//  If iCloud is not available (user not signed in), the container falls
//  back to local-only mode so the app still works for browsing.
//

import SwiftData
import CloudKit
import WidgetKit

/// Non-isolated constants accessible from any actor.
enum AppConstants {
    static let cloudKitContainerID = "iCloud.ru.protos.sharebudget"
}

@MainActor
final class DataManager {
    static let shared = DataManager()

    let container: ModelContainer

    /// Whether the container was created with CloudKit sync enabled
    let isCloudKitEnabled: Bool

    private var remoteChangeObserver: Any?

    private init() {
        let (container, cloudKit) = DataManager.createContainer()
        self.container = container
        self.isCloudKitEnabled = cloudKit

        // Forward CloudKit remote-change notifications so views that listen
        // for .modelContextDidSave also refresh when data arrives from
        // another device via iCloud sync.
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { _ in
            NotificationCenter.default.post(name: .modelContextDidSave, object: nil)
        }
    }

    private static func createContainer() -> (ModelContainer, Bool) {
        let schema = Schema(versionedSchema: SchemaV1.self)

        // Try with CloudKit first
        let cloudConfig = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .automatic
        )

        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [cloudConfig]
            )
            return (container, true)
        } catch {
            // CloudKit unavailable — fall back to local-only
            let localConfig = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .none
            )

            do {
                let container = try ModelContainer(
                    for: schema,
                    migrationPlan: AppMigrationPlan.self,
                    configurations: [localConfig]
                )
                return (container, false)
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
    }

    func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a model context save completes (either local or via remote change bridge).
    /// Views observe this to invalidate cached data.
    static let modelContextDidSave = Notification.Name("DataManager.modelContextDidSave")
}

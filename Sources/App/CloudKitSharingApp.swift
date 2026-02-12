//
//  CloudKitSharingApp.swift
//  CloudKitSharing
//
//  App entry point with CloudKit share acceptance handling.
//
//  HOW SHARE ACCEPTANCE WORKS
//  ──────────────────────────
//  1. Someone sends you a CloudKit share link
//  2. You tap it → iOS launches your app
//  3. iOS calls `userDidAcceptCloudKitShareWith` on the scene delegate
//  4. We store the metadata in CloudKitShareCoordinator
//  5. The CloudKitShareHandler overlay picks it up and calls SharingManager.acceptShare()
//
//  This is the part Apple's documentation barely explains.
//

import SwiftUI
import SwiftData
import CloudKit

// MARK: - App

@main
struct CloudKitSharingApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    init() {
        seedDataIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ListsView()
                .overlay(CloudKitShareHandler())
        }
        .modelContainer(DataManager.shared.container)
    }

    private func seedDataIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "hasSeededData") else { return }

        let context = ModelContext(DataManager.shared.container)

        let groceries = ItemList(name: "Groceries", icon: "cart.fill", colorHex: "34C759", sortOrder: 0)
        let travel = ItemList(name: "Travel Plans", icon: "airplane", colorHex: "FF9500", sortOrder: 1)

        context.insert(groceries)
        context.insert(travel)

        let items: [(String, ItemList)] = [
            ("Avocados", groceries),
            ("Sourdough bread", groceries),
            ("Oat milk", groceries),
            ("Book flights to Tokyo", travel),
            ("Reserve ryokan", travel),
        ]
        for (text, list) in items {
            let item = ListItem(text: text)
            item.list = list
            context.insert(item)
        }

        try? context.save()
        defaults.set(true, forKey: "hasSeededData")
    }
}

// MARK: - CloudKit Share Coordinator

/// Holds pending share metadata between the scene delegate callback and SwiftUI.
@MainActor
class CloudKitShareCoordinator: ObservableObject {
    static let shared = CloudKitShareCoordinator()
    @Published var pendingShareMetadata: CKShare.Metadata?

    func handleShareMetadata(_ metadata: CKShare.Metadata) {
        pendingShareMetadata = metadata
    }

    func clearPendingShare() {
        pendingShareMetadata = nil
    }
}

// MARK: - App Delegate (CloudKit share acceptance)

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Called when the user taps a CloudKit share link while the app is running
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        print("[CloudKit] Accepting share invitation")
        CloudKitShareCoordinator.shared.handleShareMetadata(metadata)
    }

    /// Called when the app is launched via a CloudKit share link
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            print("[CloudKit] Accepting share invitation from launch")
            CloudKitShareCoordinator.shared.handleShareMetadata(metadata)
        }
    }
}

// MARK: - CloudKit Share Handler (SwiftUI overlay)

/// Invisible overlay that watches for pending share metadata and accepts it.
private struct CloudKitShareHandler: View {
    @ObservedObject private var coordinator = CloudKitShareCoordinator.shared
    @Environment(\.modelContext) private var modelContext
    @State private var showingAccepted = false
    @State private var acceptedListName = ""

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: coordinator.pendingShareMetadata) { _, metadata in
                guard let metadata else { return }
                Task { @MainActor in
                    do {
                        let list = try await SharingManager.shared.acceptShare(
                            metadata,
                            context: modelContext
                        )
                        CloudKitShareCoordinator.shared.clearPendingShare()
                        acceptedListName = list.name
                        showingAccepted = true
                    } catch {
                        print("[CloudKit] Failed to accept share: \(error)")
                        CloudKitShareCoordinator.shared.clearPendingShare()
                    }
                }
            }
            .alert("Shared List Added", isPresented: $showingAccepted) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You now have access to \"\(acceptedListName)\".")
            }
    }
}

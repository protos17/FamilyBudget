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
        let context = ModelContext(DataManager.shared.container)

        // Check the database — not UserDefaults — because CloudKit sync
        // brings back data after reinstall while UserDefaults resets.
        let count = (try? context.fetchCount(FetchDescriptor<ItemList>())) ?? 0
        guard count == 0 else { return }

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
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register for silent push notifications (CloudKit sync)
        application.registerForRemoteNotifications()

        // Register CloudKit subscriptions for real-time item sync
        Task { @MainActor in
            await UserIdentityService.shared.ensureIdentityResolved()
            await SharingManager.shared.registerSubscriptions()
        }

        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    /// Handle CloudKit silent push notifications — triggers item sync
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            await SharingManager.shared.handleRemoteNotification(userInfo: userInfo)
            completionHandler(.newData)
        }
    }
}

class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Called when the user taps a CloudKit share link while the app is running
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        CloudKitShareCoordinator.shared.handleShareMetadata(metadata)
    }

    /// Called when the app is launched via a CloudKit share link
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
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
                Task {
                    defer { CloudKitShareCoordinator.shared.clearPendingShare() }
                    do {
                        let list = try await SharingManager.shared.acceptShare(
                            metadata,
                            context: modelContext
                        )
                        acceptedListName = list.name
                        showingAccepted = true
                    } catch {
                        // Share acceptance failed — metadata cleared by defer
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

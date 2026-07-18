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
import UserNotifications

// MARK: - App

@main
struct YourApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.system.rawValue
    @AppStorage("appAppearance") private var appAppearance = "system"
    
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .overlay(CloudKitShareHandler())
                .preferredColorScheme(colorScheme)
                .environment(\.locale, selectedLocale)
        }
        .modelContainer(DataManager.shared.container)
    }
    
    private var selectedLocale: Locale {
        let language = AppLanguage(rawValue: appLanguageRaw) ?? .system
        return language.locale ?? Locale.autoupdatingCurrent
    }
    
    private var colorScheme: ColorScheme? {
        switch appAppearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
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

class AppDelegate: NSObject, UIApplicationDelegate, @MainActor UNUserNotificationCenterDelegate {
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
            await SharingManager.shared.discoverSharedZones(context: DataManager.shared.container.mainContext)
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
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
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
    @State private var isAccepting = false
    @State private var showingAccepted = false
    @State private var acceptedListName = ""
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .overlay {
                if isAccepting {
                    ProgressView("Подключение к бюджету...")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .onChange(of: coordinator.pendingShareMetadata) { _, metadata in
                guard let metadata else { return }
                Task {
                    isAccepting = true
                    defer {
                        CloudKitShareCoordinator.shared.clearPendingShare()
                        isAccepting = false
                    }
                    do {
                        let list = try await SharingManager.shared.acceptShare(metadata, context: modelContext)
                        acceptedListName = list.name
                        showingAccepted = true
                    } catch {
                        errorMessage = "Не удалось подключиться к бюджету: \(error.localizedDescription)"
                        showingError = true
                    }
                }
            }
            .alert("Бюджет добавлен", isPresented: $showingAccepted) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Теперь у вас есть доступ к \"\(acceptedListName)\".")
            }
            .alert("Ошибка", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
    }
}

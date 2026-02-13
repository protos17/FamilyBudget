//
//  ListDetailView.swift
//  CloudKitSharing
//
//  Shows items in a list with permission-aware actions.
//  The toolbar includes a Share button that launches UICloudSharingController.
//

import SwiftUI
import SwiftData
import CloudKit
import Combine

struct ListDetailView: View {
    let list: ItemList
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [ListItem]
    @State private var newItemText = ""
    @FocusState private var isInputFocused: Bool

    // Sharing state
    @State private var showingShareSheet = false
    @State private var activeShare: CKShare?
    @State private var activeContainer: CKContainer?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingLeaveConfirmation = false
    @State private var isSyncing = false

    private var permissions: PermissionManager { .shared }

    init(list: ItemList) {
        self.list = list
        let listID = list.id
        _items = Query(
            filter: #Predicate<ListItem> { $0.list?.id == listID },
            sort: \.createdAt,
            order: .reverse
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 10) {
                    // Sharing status banner
                    if list.isShared {
                        sharingBanner
                    }

                    ForEach(items) { item in
                        ItemCard(
                            item: item,
                            list: list,
                            onDelete: { deleteItem(item) }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 80)
            }
            .background(Color(.systemGroupedBackground))
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No Items",
                        systemImage: "checklist",
                        description: Text("Add an item below.")
                    )
                }
            }

            // Input bar
            if permissions.canAddItem(to: list) {
                inputBar
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                shareButton
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let share = activeShare, let container = activeContainer {
                CloudSharingView(
                    list: list,
                    context: modelContext,
                    container: container,
                    share: share
                )
                .ignoresSafeArea()
            }
        }
        .alert("Sharing Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .task {
            await syncSharedItems()
        }
        .refreshable {
            await syncSharedItems()
        }
        // Periodic background sync every 5 seconds for shared lists.
        // Push notifications are unreliable on dev devices — this is the
        // primary mechanism for real-time sync (same pattern as ToMe).
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            guard list.isShared else { return }
            Task { await syncSharedItems() }
        }
        // Bridge: when CloudKit pushes remote changes, DataManager reposts as
        // .modelContextDidSave — re-sync so @Query picks up new items.
        .onReceive(NotificationCenter.default.publisher(for: .modelContextDidSave)) { _ in
            guard list.isShared else { return }
            Task { await syncSharedItems() }
        }
        .onReceive(NotificationCenter.default.publisher(for: SharingManager.itemsDidSyncNotification)) { _ in
            // Data was already synced in the push handler's context.
            // Re-sync with the view's own context so @Query picks up changes.
            Task { await syncSharedItems() }
        }
        .confirmationDialog(
            "Leave \"\(list.name)\"?",
            isPresented: $showingLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave", role: .destructive) {
                Task {
                    try? await SharingManager.shared.leaveSharedList(list, context: modelContext)
                }
            }
        } message: {
            Text("You'll lose access to this shared list. Items you added will remain for other members.")
        }
    }

    // MARK: - Sharing Banner

    private var sharingBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .foregroundStyle(.blue)
            Text(bannerText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if isSyncing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(.systemBlue).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var bannerText: String {
        UserIdentityService.shared.isCurrentUserOwner(of: list)
            ? "You're sharing this list"
            : "Shared with you"
    }

    // MARK: - Share Button

    private var shareButton: some View {
        Menu {
            if !list.isShared && permissions.canShareList(list) {
                Button {
                    presentSharing()
                } label: {
                    Label("Share List", systemImage: "person.badge.plus")
                }
            }

            if list.isShared && permissions.canManageSharing(for: list) {
                Button {
                    presentSharing()
                } label: {
                    Label("Manage Sharing", systemImage: "person.2.fill")
                }
            }

            if permissions.canLeaveList(list) {
                Button(role: .destructive) {
                    showingLeaveConfirmation = true
                } label: {
                    Label("Leave List", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        } label: {
            Image(systemName: list.isShared ? "person.2.fill" : "person.badge.plus")
        }
    }

    private func presentSharing() {
        guard SharingManager.shared.isSharingAvailable else {
            errorMessage = "iCloud is not available. Sign in to iCloud in Settings."
            showingError = true
            return
        }

        Task {
            do {
                let (share, container) = try await SharingManager.shared.fetchOrCreateShare(
                    for: list, context: modelContext
                )
                activeShare = share
                activeContainer = container
                showingShareSheet = true
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Add an item...", text: $newItemText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemFill), in: Capsule())
                .focused($isInputFocused)
                .submitLabel(.done)
                .onSubmit { addItem() }

            Button(action: addItem) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSave ? Color(hex: list.colorHex) : Color(.tertiaryLabel))
            }
            .disabled(!canSave)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var canSave: Bool {
        !newItemText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func addItem() {
        let text = newItemText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let item = ListItem(
            text: text,
            createdByUserID: UserIdentityService.shared.currentUserID
        )
        item.list = list
        modelContext.insert(item)
        try? modelContext.save()
        newItemText = ""

        // Push to CloudKit if shared
        if list.isShared {
            Task {
                try? await SharingManager.shared.pushItem(item, for: list)
            }
        }
    }

    private func deleteItem(_ item: ListItem) {
        modelContext.delete(item)
        try? modelContext.save()

        // Remove from CloudKit if shared
        if list.isShared {
            Task {
                try? await SharingManager.shared.removeItem(item, for: list)
            }
        }
    }

    private func syncSharedItems() async {
        guard list.isShared, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await SharingManager.shared.syncItems(for: list, context: modelContext)
        } catch {
            errorMessage = "Sync failed: \(error.localizedDescription)"
            showingError = true
        }
    }
}

// MARK: - Item Card

private struct ItemCard: View {
    let item: ListItem
    let list: ItemList
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle")
                .font(.body)
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(item.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            if PermissionManager.shared.canDelete(item: item, in: list) {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

//
//  ListsView.swift
//  CloudKitSharing
//
//  Shows all lists. Shared lists display a badge with participant count.
//

import SwiftUI
import SwiftData

struct ListsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ItemList.sortOrder) private var lists: [ItemList]
    @State private var showingAddList = false
    @State private var newListName = ""
    @State private var sharingEndedName: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(lists) { list in
                        NavigationLink(destination: ListDetailView(list: list)) {
                            ListRow(list: list)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Lists")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddList = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New List", isPresented: $showingAddList) {
                TextField("Name", text: $newListName)
                Button("Add") { addList() }
                Button("Cancel", role: .cancel) { newListName = "" }
            }
            .overlay {
                if lists.isEmpty {
                    ContentUnavailableView(
                        "No Lists",
                        systemImage: "list.bullet",
                        description: Text("Tap + to create your first list.")
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: SharingManager.sharingEndedNotification)) { notification in
                if let name = notification.userInfo?["listName"] as? String {
                    sharingEndedName = name
                }
            }
            .alert("Sharing Ended", isPresented: .init(
                get: { sharingEndedName != nil },
                set: { if !$0 { sharingEndedName = nil } }
            )) {
                Button("OK", role: .cancel) { sharingEndedName = nil }
            } message: {
                if let name = sharingEndedName {
                    Text("\"\(name)\" is no longer shared. A local copy has been kept.")
                }
            }
        }
    }

    private func addList() {
        guard !newListName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let list = ItemList(name: newListName, sortOrder: lists.count)
        modelContext.insert(list)
        try? modelContext.save()
        newListName = ""
    }
}

// MARK: - List Row

private struct ListRow: View {
    let list: ItemList

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: list.icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color(hex: list.colorHex))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(list.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)

                    if list.isShared {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }

                Text(itemCountLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var itemCountLabel: String {
        let count = list.items?.count ?? 0
        return count == 1 ? "1 item" : "\(count) items"
    }
}

// MARK: - Color Hex

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

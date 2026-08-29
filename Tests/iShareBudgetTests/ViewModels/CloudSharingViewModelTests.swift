import Testing
import SwiftData
import UIKit
@testable import iShareBudget

@MainActor
@Suite("CloudSharingViewModel")
struct CloudSharingViewModelTests {
    @Test("itemTitle mirrors the list's name")
    func itemTitle() throws {
        let context = try TestModelContainer.makeContext()
        let list = MockData.makeAccount(name: "Семейный бюджет")
        let viewModel = CloudSharingViewModel(list: list, context: context)

        #expect(viewModel.itemTitle == "Семейный бюджет")
    }

    @Test("itemThumbnailData renders a square image")
    func thumbnailData() throws {
        let context = try TestModelContainer.makeContext()
        let list = MockData.makeAccount(icon: "wallet.pass.fill", colorHex: "007AFF")
        let viewModel = CloudSharingViewModel(list: list, context: context)

        let data = try #require(viewModel.itemThumbnailData())
        let image = try #require(UIImage(data: data))
        // PNG round-tripping discards the renderer's scale, so pixel dimensions
        // (not points) are the only thing safe to assert on here.
        let pixelWidth = try #require(image.cgImage?.width)
        let pixelHeight = try #require(image.cgImage?.height)
        #expect(pixelWidth == pixelHeight)
        #expect(pixelWidth > 0)
    }

    @Test("itemThumbnailData still returns data for an unknown SF Symbol name")
    func thumbnailDataUnknownSymbol() throws {
        let context = try TestModelContainer.makeContext()
        let list = MockData.makeAccount(icon: "not-a-real-symbol-xyz")
        let viewModel = CloudSharingViewModel(list: list, context: context)

        #expect(viewModel.itemThumbnailData() != nil)
    }

    @Test("stopSharing delegates to the sharing service")
    func stopSharingDelegates() async throws {
        let context = try TestModelContainer.makeContext()
        let list = MockData.makeSharedAccount()
        let sharing = MockSharingService()
        let viewModel = CloudSharingViewModel(list: list, context: context, sharing: sharing)

        await viewModel.stopSharing()

        #expect(sharing.stoppedLists.map(\.id) == [list.id])
    }
}

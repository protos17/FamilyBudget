//
//  CloudSharingView.swift
//  CloudKitSharing
//
//  SwiftUI wrapper for UICloudSharingController.
//
//  UICloudSharingController is Apple's built-in UI for:
//  • Sending share invitations (via Messages, Mail, link)
//  • Managing existing participants (change permissions, remove)
//  • Stopping sharing entirely
//
//  You don't need to build any of this UI yourself — Apple provides it.
//  You just need to give it a CKShare and CKContainer.
//

import SwiftUI
import CloudKit
import SwiftData

struct CloudSharingView: UIViewControllerRepresentable {
    let list: Account
    let context: ModelContext
    let container: CKContainer
    let share: CKShare

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: self.container)
        controller.delegate = context.coordinator
        // Demo permission model supports owner/member write access only.
        // Avoid exposing read-only participant mode until app permissions
        // and UI behaviors account for it end-to-end.
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.modalPresentationStyle = .formSheet
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: CloudSharingViewModel(list: list, context: context))
    }

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let viewModel: CloudSharingViewModel

        init(viewModel: CloudSharingViewModel) {
            self.viewModel = viewModel
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            // Error is shown by UICloudSharingController
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            viewModel.itemTitle
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            viewModel.itemThumbnailData()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            Task { @MainActor in
                await viewModel.stopSharing()
            }
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}
    }
}

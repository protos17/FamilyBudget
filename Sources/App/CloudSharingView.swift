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
    let list: ItemList
    let context: ModelContext
    let container: CKContainer
    let share: CKShare

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadWrite, .allowReadOnly, .allowPrivate]
        controller.modalPresentationStyle = .formSheet
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let parent: CloudSharingView

        init(_ parent: CloudSharingView) {
            self.parent = parent
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            // Error is shown by UICloudSharingController
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            parent.list.name
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            // Generate a thumbnail with the list's icon and color
            let size = CGSize(width: 120, height: 120)
            let color = UIColor(Color(hex: parent.list.colorHex))

            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { ctx in
                let rect = CGRect(origin: .zero, size: size)
                UIBezierPath(roundedRect: rect, cornerRadius: 24).addClip()
                color.setFill()
                ctx.fill(rect)

                let config = UIImage.SymbolConfiguration(pointSize: 48, weight: .medium)
                if let symbol = UIImage(systemName: parent.list.icon, withConfiguration: config) {
                    let tinted = symbol.withTintColor(.white, renderingMode: .alwaysOriginal)
                    let origin = CGPoint(
                        x: (size.width - tinted.size.width) / 2,
                        y: (size.height - tinted.size.height) / 2
                    )
                    tinted.draw(at: origin)
                }
            }
            return image.pngData()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            Task { @MainActor in
                do {
                    try await SharingManager.shared.stopSharing(parent.list, context: parent.context)
                } catch {
                    // Silently fail — user can retry from the menu
                }
            }
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}
    }
}

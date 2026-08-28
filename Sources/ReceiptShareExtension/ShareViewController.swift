//
//  ShareViewController.swift
//  ReceiptShareExtension
//
//  Receives a shared receipt photo from the system share sheet and hands it
//  off to the main app via an App Group file + custom URL scheme. The
//  extension itself never talks to the AI API or the SwiftData/CloudKit
//  store — that all happens in the host app, reusing existing code.
//

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private static let appGroupID = "group.ru.protos.sharebudget"
    private static let pendingReceiptRelativePath = "PendingReceipt/receipt.jpg"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        spinner.startAnimating()

        handleSharedItem()
    }

    private func handleSharedItem() {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let provider = item.attachments?.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) })
        else {
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            return
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
            DispatchQueue.main.async {
                self?.finish(with: data)
            }
        }
    }

    private func finish(with data: Data?) {
        guard
            let data,
            let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)
        else {
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            return
        }

        let fileURL = containerURL.appendingPathComponent(Self.pendingReceiptRelativePath)
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)

        if let openURL = URL(string: "ishare://receipt") {
            extensionContext?.open(openURL) { [weak self] _ in
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
        } else {
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
}

//
//  CloudSharingViewModel.swift
//  CloudKitSharing
//
//  Created by Danil on 17.07.2026.
//

import SwiftUI
import SwiftData

@MainActor
final class CloudSharingViewModel: ObservableObject {
    let list: Account
    let context: ModelContext

    init(list: Account, context: ModelContext) {
        self.list = list
        self.context = context
    }

    var itemTitle: String? {
        list.name
    }

    func itemThumbnailData() -> Data? {
        let size = CGSize(width: 120, height: 120)
        let color = UIColor(Color(hex: list.colorHex))

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            UIBezierPath(roundedRect: rect, cornerRadius: 24).addClip()
            color.setFill()
            ctx.fill(rect)

            let config = UIImage.SymbolConfiguration(pointSize: 48, weight: .medium)
            if let symbol = UIImage(systemName: list.icon, withConfiguration: config) {
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

    func stopSharing() async {
        try? await SharingManager.shared.stopSharing(list, context: context)
    }
}

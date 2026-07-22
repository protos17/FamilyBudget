//
//  DefaultCategories.swift
//  iShareBudget
//
//  Created by Danil on 21.07.2026.
//

import Foundation
import SwiftData

enum DefaultCategories {
    struct Blueprint {
        let id: UUID
        let name: String
        let icon: String
        let colorHex: String
        let kind: CategoryKind
    }

    static let all: [Blueprint] = [
        Blueprint(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Продукты", icon: "cart.fill", colorHex: "2ECC71", kind: .expense),
        Blueprint(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Транспорт", icon: "car.fill", colorHex: "3498DB", kind: .expense),
        Blueprint(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Жильё и коммуналка", icon: "house.fill", colorHex: "E67E22", kind: .expense),
        Blueprint(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "Здоровье", icon: "cross.case.fill", colorHex: "E74C3C", kind: .expense),
        Blueprint(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, name: "Развлечения", icon: "gamecontroller.fill", colorHex: "9B59B6", kind: .expense),
        Blueprint(id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!, name: "Одежда", icon: "tshirt.fill", colorHex: "1ABC9C", kind: .expense),
        Blueprint(id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!, name: "Образование", icon: "graduationcap.fill", colorHex: "34495E", kind: .expense),
        Blueprint(id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!, name: "Кафе и рестораны", icon: "fork.knife", colorHex: "F39C12", kind: .expense),
        Blueprint(id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!, name: "Подписки", icon: "repeat.circle.fill", colorHex: "8E44AD", kind: .expense),
        Blueprint(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!, name: "Связь и интернет", icon: "wifi", colorHex: "2980B9", kind: .expense),
        Blueprint(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!, name: "Спорт", icon: "figure.run", colorHex: "16A085", kind: .expense),
        Blueprint(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!, name: "Красота", icon: "sparkles", colorHex: "FD79A8", kind: .expense),
        Blueprint(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000D")!, name: "Подарки", icon: "gift.fill", colorHex: "D35400", kind: .expense),
        Blueprint(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000E")!, name: "Путешествия", icon: "airplane", colorHex: "0984E3", kind: .expense),
        Blueprint(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000F")!, name: "Питомцы", icon: "pawprint.fill", colorHex: "27AE60", kind: .expense),
        Blueprint(id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!, name: "Дети", icon: "figure.2.and.child.holdinghands", colorHex: "FF7675", kind: .expense),
        Blueprint(id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!, name: "Автомобиль", icon: "car.side.fill", colorHex: "636E72", kind: .expense),
        Blueprint(id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!, name: "Техника", icon: "desktopcomputer", colorHex: "00B894", kind: .expense),
        Blueprint(id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!, name: "Хобби", icon: "paintbrush.fill", colorHex: "E17055", kind: .expense),
        Blueprint(id: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!, name: "Прочее", icon: "ellipsis.circle.fill", colorHex: "95A5A6", kind: .expense),
        Blueprint(id: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!, name: "Бытовая химия", icon: "waterbottle.fill", colorHex: "D35400", kind: .expense)
    ]

    static func seed(into account: Account, context: ModelContext) {
        let existingIDs = Set((account.categories ?? []).map { $0.id })

        for (index, blueprint) in all.enumerated() {
            guard !existingIDs.contains(blueprint.id) else { continue }

            let category = Category(
                id: blueprint.id,
                name: blueprint.name,
                icon: blueprint.icon,
                colorHex: blueprint.colorHex,
                kind: blueprint.kind,
                sortOrder: index
            )
            category.account = account
            context.insert(category)
        }
    }
}

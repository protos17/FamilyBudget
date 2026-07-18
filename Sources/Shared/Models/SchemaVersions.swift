//
//  SchemaVersions.swift
//  CloudKitSharing
//
//  Versioned schemas and migration plan.
//  All targets must use the same migration plan.
//

import SwiftData

enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Account.self, Transaction.self]
    }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV2.self]
    }
    static var stages: [MigrationStage] { [] }
}

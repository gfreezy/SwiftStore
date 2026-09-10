// Created by swiftstore CLI. Commit this file; manual edits are allowed.
import Foundation
import SwiftStoreCore

public enum StoreMigrations {
    public static func all(bundle: Bundle = .main, subdirectory: String? = nil) throws -> [StoreMigration] {
        var catalog = StoreMigrationCatalog()
        try catalog.append(id: "001_initial",
            delta: try SchemaDelta.load("001_initial.schema.json", in: bundle, subdirectory: subdirectory),
            up: Migration_001.up)
        try catalog.append(id: "002_display_name",
            delta: try SchemaDelta.load("002_display_name.schema.json", in: bundle, subdirectory: subdirectory),
            up: Migration_002.up)
        try catalog.append(id: "003_update_timestamps",
            delta: try SchemaDelta.load("003_update_timestamps.schema.json", in: bundle, subdirectory: subdirectory),
            up: Migration_003.up)
        try catalog.append(id: "004_trigger_format",
            delta: try SchemaDelta.load("004_trigger_format.schema.json", in: bundle, subdirectory: subdirectory),
            up: Migration_004.up)
        return catalog.migrations
    }
}

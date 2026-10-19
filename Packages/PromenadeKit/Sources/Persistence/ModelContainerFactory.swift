import Foundation
import SwiftData

public enum ModelContainerFactory {
  public static func make(inMemory: Bool = false) throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV1.self)
    let configuration = ModelConfiguration(
      schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
    return try make(schema: schema, configuration: configuration)
  }

  /// Creates a local store at an explicit URL, useful for isolated file-backed stores.
  public static func make(url: URL) throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV1.self)
    let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
    return try make(schema: schema, configuration: configuration)
  }

  private static func make(schema: Schema, configuration: ModelConfiguration) throws
    -> ModelContainer
  {
    try ModelContainer(
      for: schema, migrationPlan: PromenadeMigrationPlan.self, configurations: [configuration])
  }
}

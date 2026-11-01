import Domain
import Foundation
import SwiftData

/// Reads a whole session, with its points, away from the main thread: a long walk holds tens of
/// thousands of points, and mapping them takes long enough to freeze the UI.
public struct SessionRecordLoader: Sendable {
  private let container: ModelContainer

  public init(container: ModelContainer) {
    self.container = container
  }

  @concurrent
  public func session(id: UUID) async throws -> SessionRecord? {
    // A fresh context sees saves from the recording actor instead of cached models, and reading
    // outside that actor keeps a long read from delaying recording.
    let context = ModelContext(container)
    context.autosaveEnabled = false
    return try context.sessionRecord(id: id)
  }
}

extension ModelContext {
  func sessionRecord(id: UUID) throws -> SessionRecord? {
    var descriptor = FetchDescriptor<WalkingSession>(predicate: #Predicate { $0.id == id })
    descriptor.fetchLimit = 1
    return try fetch(descriptor).first?.record()
  }
}

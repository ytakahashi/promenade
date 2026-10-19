import Domain
import Foundation
import SwiftData

/// Synchronous reads let launch recovery decide before background launch time runs out.
@MainActor
public struct SessionReader {
  private let context: ModelContext

  public init(context: ModelContext) {
    self.context = context
  }

  public func session(id: UUID) throws -> SessionRecord? {
    var descriptor = FetchDescriptor<WalkingSession>(predicate: #Predicate { $0.id == id })
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first?.record()
  }

  public func unfinishedSession() throws -> SessionRecord? {
    var descriptor = unfinishedDescriptor()
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first?.record()
  }

  /// Newest first. Recovery can finish surplus sessions through the recording actor.
  public func unfinishedSessions() throws -> [SessionRecord] {
    try context.fetch(unfinishedDescriptor()).map { try $0.record() }
  }

  private func unfinishedDescriptor() -> FetchDescriptor<WalkingSession> {
    let finished = SessionState.finished.rawValue
    return FetchDescriptor(
      predicate: #Predicate { $0.stateRaw != finished },
      sortBy: [SortDescriptor(\.startDate, order: .reverse), SortDescriptor(\.id)]
    )
  }
}

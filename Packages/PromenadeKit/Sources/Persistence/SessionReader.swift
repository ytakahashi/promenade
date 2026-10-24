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

  /// Finished sessions, newest first, without loading segments or points.
  public func finishedSessions() throws -> [SessionListItem] {
    let finished = SessionState.finished.rawValue
    var descriptor = FetchDescriptor<WalkingSession>(
      predicate: #Predicate { $0.stateRaw == finished },
      sortBy: [SortDescriptor(\.startDate, order: .reverse), SortDescriptor(\.id)]
    )
    // Lists can hold thousands of sessions; read only the saved metrics.
    descriptor.propertiesToFetch = [
      \.id, \.startDate, \.timeZoneIdentifier, \.distance, \.walkingDuration, \.steps,
    ]
    return try context.fetch(descriptor).map { $0.listItem() }
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

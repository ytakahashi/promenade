import Foundation

public protocol DerivedDataRecomputing: Sendable {
  /// Recomputes saved metrics from raw points. Missing or already current sessions return false.
  /// Unfinished sessions throw `PersistenceError.sessionNotFinished`.
  func recomputeDerivedData(sessionID: UUID) async throws -> Bool
}

import Foundation

/// Deletes saved walks, without exposing the recording operations of `TrackingStore`.
public protocol SessionDeleting: Sendable {
  /// Deletes a finished session with its segments and points. A missing session is not an error.
  /// Throws `PersistenceError.sessionNotFinished` for a session still being recorded.
  func deleteSession(id: UUID) async throws
}

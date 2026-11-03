import Foundation

/// Edits saved walks without exposing recording operations.
public protocol SessionTrimming: Sendable {
  /// Ends a finished session at `date` and permanently deletes everything after it.
  /// - Parameter steps: Fallback steps of the entire last remaining segment up to `date`, or nil
  ///   when unmeasured. Used only when `SessionRecord.trimmed(endingAt:)` retains no measurement.
  /// - Throws: A `PersistenceError` for a missing or unfinished session, an invalid date, or
  ///   invalid stored data or structure; or an error from saving the changes.
  func trimEnd(sessionID: UUID, at date: Date, steps: Int?) async throws
}

import Domain
import Foundation

/// An accepted point remains in the store even if its batch could not be saved.
public enum PointAppendResult: Sendable {
  /// Accepted and pending; no save was attempted.
  case accepted
  /// Accepted, and the batch including this point (and any earlier pending points) was saved.
  case saved
  case pendingSaveFailure(any Error)
}

/// State transitions are saved atomically. A failed transition must be explicitly retried;
/// a later flush saves pending points without applying that transition.
///
/// Transitions that close a segment take the closed segment's `steps` (`nil` when unmeasured) so
/// the step count is saved with the closure. It is ignored when there is no open segment.
public protocol TrackingStore: Actor {
  func createSession(id: UUID, startDate: Date, timeZone: TimeZone) async throws
  /// Throws only before accepting the point. A pending save failure must be retried with `flush`.
  @discardableResult
  func append(_ point: TrackPoint, sessionID: UUID) async throws -> PointAppendResult
  /// Closes the open segment as paused and changes the session state in the same save.
  /// After access loss, creates an empty paused segment so the preceding interruption is retained.
  func pause(sessionID: UUID, at date: Date, steps: Int?) async throws
  /// Opens a segment and changes the paused session back to recording.
  func resume(sessionID: UUID, at date: Date) async throws
  /// Splits an open segment for signal loss or interruption without changing session state.
  func splitSegment(
    sessionID: UUID, closingAt: Date, reason: SegmentEndReason, steps: Int?, nextStart: Date
  ) async throws
  /// Closes the open segment as interrupted, leaving the session in recording state.
  func interruptSegment(sessionID: UUID, at date: Date, steps: Int?) async throws
  /// Opens a segment in a recording session that currently has none open.
  func openSegment(sessionID: UUID, at date: Date) async throws
  func finish(sessionID: UUID, at date: Date, steps: Int?) async throws
  /// Deletes the session in any state with its segments and points. Used only to discard a walk
  /// being finished; a missing session is not an error.
  func discard(sessionID: UUID) async throws
  func flush() async throws
  func loadSession(id: UUID) async throws -> SessionRecord?
}

import Domain
import Foundation

/// State transitions are saved atomically. A failed transition must be explicitly retried;
/// a later flush saves pending points without applying that transition.
public protocol TrackingStore: Actor {
  func createSession(id: UUID, startDate: Date, timeZone: TimeZone) throws
  /// If a batch save fails, the point remains pending. Retry `flush`, not the same append.
  func append(_ point: TrackPoint, sessionID: UUID) throws
  /// Closes the open segment as paused and changes the session state in the same save.
  func pause(sessionID: UUID, at date: Date) throws
  /// Opens a segment and changes the paused session back to recording.
  func resume(sessionID: UUID, at date: Date) throws
  /// Splits an open segment for signal loss or interruption without changing session state.
  func splitSegment(
    sessionID: UUID, closingAt: Date, reason: SegmentEndReason, nextStart: Date
  ) throws
  /// Closes the open segment as interrupted, leaving the session in recording state.
  func interruptSegment(sessionID: UUID, at date: Date) throws
  /// Opens a segment in a recording session that currently has none open.
  func openSegment(sessionID: UUID, at date: Date) throws
  func finish(sessionID: UUID, at date: Date) throws
  func flush() throws
  func loadSession(id: UUID) throws -> SessionRecord?
}

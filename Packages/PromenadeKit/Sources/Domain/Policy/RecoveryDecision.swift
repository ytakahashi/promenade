import Foundation

/// A recovery action for the caller to execute; deciding does not modify the session.
public enum RecoveryDecision: Sendable, Equatable {
  case none
  case autoFinish(at: Date)
  case restorePaused
  case autoResume(ResumeMode)
  /// On resume, the caller closes the last segment at `lastActivity` as interrupted if it is still
  /// open, then opens a new segment.
  case askUser(lastActivity: Date)
}

/// How to continue recording after a background relaunch.
public enum ResumeMode: Sendable, Equatable {
  /// The last segment is still open and the gap is short; keep appending to it.
  case continueSegment
  /// Close the open last segment at `closingAt` as interrupted, then open a new segment.
  case closeAndOpen(closingAt: Date)
  /// The last segment is already closed, e.g. location access was lost before termination;
  /// open a new segment without closing anything.
  case openNew
}

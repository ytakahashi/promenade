import Domain
import Foundation
import Sensors

public enum TrackingPhase: Sendable, Equatable {
  case idle
  case recording(LocationStatus)
  case paused
  case awaitingRecoveryDecision(lastActivity: Date)
}

public enum LocationStatus: Sendable, Equatable {
  case active
  case searching
  case waitingForAccess(LocationAccessIssue)
}

public enum RecoveryChoice: Sendable { case resume, finish }

public enum TrackingNotice: Sendable, Equatable {
  case autoFinished(sessionID: UUID)
}

public enum TrackingFailure: Sendable, Equatable {
  case access(LocationAccessIssue)
  case sensor
  case persistence
}

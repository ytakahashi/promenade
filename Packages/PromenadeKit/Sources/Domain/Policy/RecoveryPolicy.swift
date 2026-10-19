import Foundation

public struct RecoveryPolicy: Sendable {
  public var configuration: TrackingConfiguration

  public init(configuration: TrackingConfiguration = .default) {
    self.configuration = configuration
  }

  public func decide(session: SessionRecord?, launch: LaunchContext, now: Date) -> RecoveryDecision
  {
    guard let session, session.state != .finished else { return .none }
    let lastActivity = session.lastActivityDate
    let gap = now.timeIntervalSince(lastActivity)
    // Expiry takes priority even for paused sessions and foreground launches.
    if gap > configuration.autoFinishThreshold {
      return .autoFinish(at: lastActivity)
    }
    if session.state == .paused { return .restorePaused }
    switch launch {
    case .background:
      // A recording session may have no open segment: location access was lost before
      // termination, so the segment was closed as interrupted and nothing can be continued.
      guard session.hasOpenSegment else { return .autoResume(.openNew) }
      return .autoResume(
        gap > configuration.relaunchSplitThreshold
          ? .closeAndOpen(closingAt: lastActivity) : .continueSegment)
    case .foreground:
      return .askUser(lastActivity: lastActivity)
    }
  }
}

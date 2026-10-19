import Foundation
import Testing

@testable import Domain

struct RecoveryPolicyTests {
  /// A session whose only segment started at `Date.reference` and is still open.
  private func session(state: SessionState = .recording) -> SessionRecord {
    SessionRecord(
      id: UUID(), startDate: .reference, state: state, timeZoneIdentifier: "Asia/Tokyo",
      segments: [SegmentRecord(index: 0, startDate: .reference)])
  }

  @Test(arguments: [LaunchContext.background, .foreground])
  func absentAndFinishedSessionsNeedNoRecovery(_ launch: LaunchContext) {
    let now = Date.reference.addingTimeInterval(100_000)
    let policy = RecoveryPolicy()
    #expect(policy.decide(session: nil, launch: launch, now: now) == .none)
    #expect(policy.decide(session: session(state: .finished), launch: launch, now: now) == .none)
  }

  @Test(arguments: [SessionState.recording, .paused], [LaunchContext.background, .foreground])
  func expiryTakesPriorityOverOtherRecoveryActions(_ state: SessionState, _ launch: LaunchContext) {
    #expect(
      RecoveryPolicy().decide(
        session: session(state: state), launch: launch,
        now: .reference.addingTimeInterval(21_601)
      ) == .autoFinish(at: .reference))
  }

  @Test(arguments: [LaunchContext.background, .foreground], [0.0, 21_599, 21_600])
  func restoresPausedSessionsThroughExpiryBoundary(_ launch: LaunchContext, _ gap: TimeInterval) {
    #expect(
      RecoveryPolicy().decide(
        session: session(state: .paused), launch: launch, now: .reference.addingTimeInterval(gap)
      ) == .restorePaused)
  }

  @Test(arguments: [-10.0, 0, 59, 60, 61, 21_600])
  func backgroundResumeSplitsOnlyAfterThreshold(_ gap: TimeInterval) {
    #expect(
      RecoveryPolicy().decide(
        session: session(), launch: .background, now: .reference.addingTimeInterval(gap)
      ) == .autoResume(gap > 60 ? .closeAndOpen(closingAt: .reference) : .continueSegment))
  }

  @Test(arguments: [0.0, 61])
  func backgroundResumeOpensNewSegmentWhenLastSegmentIsClosed(_ sinceClose: TimeInterval) {
    // Location access was lost before termination: the segment was closed as interrupted.
    var record = session()
    record.segments[0].endDate = .reference.addingTimeInterval(30)
    record.segments[0].endReason = .interrupted
    #expect(
      RecoveryPolicy().decide(
        session: record, launch: .background,
        now: .reference.addingTimeInterval(30 + sinceClose)
      ) == .autoResume(.openNew))
  }

  @Test func backgroundResumeOpensNewSegmentWhenSessionHasNoSegments() {
    var record = session()
    record.segments = []
    #expect(
      RecoveryPolicy().decide(
        session: record, launch: .background, now: .reference.addingTimeInterval(10)
      ) == .autoResume(.openNew))
  }

  @Test(arguments: [-10.0, 0, 60, 61, 21_600])
  func foregroundRecordingAsksUserThroughExpiryBoundary(_ gap: TimeInterval) {
    #expect(
      RecoveryPolicy().decide(
        session: session(), launch: .foreground, now: .reference.addingTimeInterval(gap)
      ) == .askUser(lastActivity: .reference))
  }

  @Test func usesLastActivityForExpiryAndSplitDate() {
    var record = session()
    record.segments = [
      SegmentRecord(
        index: 0, startDate: .reference.addingTimeInterval(10),
        points: [.fixture(seconds: 100)]
      )
    ]
    let policy = RecoveryPolicy()
    #expect(
      policy.decide(
        session: record, launch: .background, now: .reference.addingTimeInterval(160)
      ) == .autoResume(.continueSegment))
    #expect(
      policy.decide(
        session: record, launch: .background, now: .reference.addingTimeInterval(161)
      ) == .autoResume(.closeAndOpen(closingAt: .reference.addingTimeInterval(100))))
    #expect(
      policy.decide(
        session: record, launch: .foreground, now: .reference.addingTimeInterval(21_700)
      ) == .askUser(lastActivity: .reference.addingTimeInterval(100)))
    #expect(
      policy.decide(
        session: record, launch: .background, now: .reference.addingTimeInterval(21_701)
      ) == .autoFinish(at: .reference.addingTimeInterval(100)))
  }

  @Test func emptyResumedSegmentAndPauseEndCountAsActivity() {
    var record = session()
    record.segments = [SegmentRecord(index: 0, startDate: .reference.addingTimeInterval(100))]
    let now = Date.reference.addingTimeInterval(150)
    #expect(
      RecoveryPolicy().decide(session: record, launch: .background, now: now)
        == .autoResume(.continueSegment))
    record.state = .paused
    record.segments[0].endDate = .reference.addingTimeInterval(120)
    record.segments[0].endReason = .paused
    #expect(
      RecoveryPolicy().decide(
        session: record, launch: .foreground, now: .reference.addingTimeInterval(21_721)
      ) == .autoFinish(at: .reference.addingTimeInterval(120)))
  }

  @Test func usesConfiguredThresholds() {
    var configuration = TrackingConfiguration.default
    configuration.relaunchSplitThreshold = 10
    configuration.autoFinishThreshold = 20
    let policy = RecoveryPolicy(configuration: configuration)
    #expect(
      policy.decide(
        session: session(), launch: .background, now: .reference.addingTimeInterval(10)
      ) == .autoResume(.continueSegment))
    #expect(
      policy.decide(
        session: session(), launch: .background, now: .reference.addingTimeInterval(11)
      ) == .autoResume(.closeAndOpen(closingAt: .reference)))
    #expect(
      policy.decide(
        session: session(), launch: .background, now: .reference.addingTimeInterval(20)
      ) == .autoResume(.closeAndOpen(closingAt: .reference)))
    #expect(
      policy.decide(
        session: session(), launch: .background, now: .reference.addingTimeInterval(21)
      ) == .autoFinish(at: .reference))
  }
}

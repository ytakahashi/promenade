import Foundation
import Testing
import Tracking

@testable import Features

@MainActor
struct TrackingControlStateTests {
  @Test func idleOffersStartOnlyWithoutALiveSession() {
    #expect(TrackingControlState(phase: .idle, hasLiveSession: false) == .start)
    #expect(TrackingControlState(phase: .idle, hasLiveSession: true) == .restoring)
  }

  @Test(arguments: [TrackingPhase.recording(.active), .recording(.searching)])
  func recordingOffersPauseAndFinish(_ phase: TrackingPhase) {
    #expect(TrackingControlState(phase: phase, hasLiveSession: true) == .recording)
  }

  @Test func pausedOffersResumeAndFinish() {
    #expect(TrackingControlState(phase: .paused, hasLiveSession: true) == .paused)
  }

  @Test func recoveryDecisionHidesTheControls() {
    let phase = TrackingPhase.awaitingRecoveryDecision(
      lastActivity: Date(timeIntervalSinceReferenceDate: 0))
    #expect(TrackingControlState(phase: phase, hasLiveSession: true) == .hidden)
  }
}

import Foundation
import Testing
import Tracking

@testable import Features

@MainActor
struct LiveMetricsViewTests {
  @Test(arguments: [TrackingPhase.recording(.searching), .recording(.active), .paused])
  func clockRunsWhileRecordingStateIsConfirmed(_ phase: TrackingPhase) {
    #expect(LiveMetricsView.isClockRunning(in: phase))
  }

  @Test(arguments: [
    TrackingPhase.idle,
    .awaitingRecoveryDecision(lastActivity: Date(timeIntervalSinceReferenceDate: 0)),
  ])
  func clockStopsWhileRecoveryIsUnresolved(_ phase: TrackingPhase) {
    #expect(!LiveMetricsView.isClockRunning(in: phase))
  }
}

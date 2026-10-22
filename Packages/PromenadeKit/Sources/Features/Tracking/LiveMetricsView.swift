import Domain
import SwiftUI
import Tracking

struct LiveMetricsView: View {
  let session: LiveSession
  let isClockRunning: Bool

  /// Recovery keeps the last segment open while the launch is resolved or the user decides, so
  /// timing up to now would count the time the app was gone as walking. Only confirmed recording
  /// or paused phases may advance. Background `.autoResume` reports `.recording` before it closes
  /// a stale segment, but that window is bounded and is not presented in the foreground.
  static func isClockRunning(in phase: TrackingPhase) -> Bool {
    switch phase {
    case .recording, .paused: true
    case .idle, .awaitingRecoveryDecision: false
    }
  }

  var body: some View {
    if isClockRunning {
      // Keep time observation below the map: a tick must not rebuild route coordinates or its camera.
      TimelineView(.periodic(from: .now, by: 1)) { context in
        panel(asOf: context.date)
      }
    } else {
      panel(asOf: session.lastActivity)
    }
  }

  private func panel(asOf date: Date) -> some View {
    MetricsPanel(
      metrics: SessionMetrics(
        distance: session.route.distance, timing: session.timing(asOf: date), steps: nil))
  }
}

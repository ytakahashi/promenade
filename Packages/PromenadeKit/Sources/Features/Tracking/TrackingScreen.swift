import SwiftUI
import Tracking

struct TrackingScreen: View {
  let engine: TrackingEngine
  let presentation: TrackingPresentation
  let locationAccess: LocationAccessState
  @State private var metricsHeight: CGFloat = 0

  /// Share of the screen the metrics may take before scrolling; the controls sit below them.
  private static let metricsHeightRatio: CGFloat = 0.5

  var body: some View {
    GeometryReader { geometry in
      let maxMetricsHeight = geometry.size.height * Self.metricsHeightRatio
      VStack(spacing: 0) {
        TrackingMapView(session: engine.liveSession, locationAccess: locationAccess)
        if let session = engine.liveSession {
          ScrollView {
            LiveMetricsView(
              session: session, isClockRunning: LiveMetricsView.isClockRunning(in: engine.phase)
            )
            .onGeometryChange(for: CGFloat.self) {
              $0.size.height
            } action: {
              metricsHeight = $0
            }
          }
          .scrollBounceBehavior(.basedOnSize)
          .frame(
            height: min(metricsHeight > 0 ? metricsHeight : maxMetricsHeight, maxMetricsHeight))
        }
        // Outside the scroll view so scrolling cannot compete with the Finish hold gesture.
        TrackingActions(engine: engine, presentation: presentation)
      }
    }
    .trackingDialogAlert(
      presentation.dialog(for: engine), failure: engine.operationFailure,
      confirm: {
        // Starts synchronously so the presentation marks the dialog as answered before the alert
        // re-reads it; a plain Task would let the still-pending dialog be presented again.
        Task.immediate { await presentation.confirmDialog(engine) }
      },
      cancel: { presentation.cancelDialog(engine) })
  }
}

/// Reads the engine's operation state separately so busy and failure changes do not re-evaluate
/// the map's parent.
private struct TrackingActions: View {
  let engine: TrackingEngine
  let presentation: TrackingPresentation

  var body: some View {
    TrackingControls(
      state: TrackingControlState(phase: engine.phase, hasLiveSession: engine.hasLiveSession),
      failure: presentation.displayedFailure(engine),
      isEnabled: presentation.canOperate(engine),
      isWorking: engine.isBusy || presentation.isPerforming,
      start: { Task.immediate { await presentation.start(engine) } },
      pause: { presentation.requestPause(engine) },
      resume: { presentation.requestResume(engine) },
      finish: { presentation.requestFinish(engine) },
      dismissFailure: { engine.clearFailure() })
  }
}

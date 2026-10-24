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
          .overlay(alignment: .top) {
            TrackingBanner(engine: engine, presentation: presentation).padding()
          }
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
        TrackingActions(
          engine: engine, presentation: presentation, locationAccess: locationAccess)
      }
    }
    .trackingDialogAlert(
      presentation.dialog(for: engine), failure: engine.operationFailure,
      confirm: {
        // Starts synchronously so the presentation marks the dialog as answered before the alert
        // re-reads it; a plain Task would let the still-pending dialog be presented again.
        Task.immediate { await presentation.confirmDialog(engine) }
      },
      discard: { Task.immediate { await presentation.discardFinish(engine) } },
      cancel: { presentation.cancelDialog(engine) }
    )
    .onChange(of: locationAccess) { _, access in
      presentation.locationAccessChanged(to: access, engine)
    }
  }
}

/// Reads the engine's operation state separately so busy and failure changes do not re-evaluate
/// the map's parent.
private struct TrackingActions: View {
  let engine: TrackingEngine
  let presentation: TrackingPresentation
  let locationAccess: LocationAccessState

  var body: some View {
    let notice = accessNotice
    let state = TrackingControlState(
      phase: engine.phase, hasLiveSession: engine.hasLiveSession,
      startAllowed: notice?.allowsStart ?? true)
    if notice != nil || state != .hidden {
      VStack(spacing: 12) {
        if let notice { LocationAccessView(notice: notice) }
        TrackingControls(
          state: state,
          isEnabled: presentation.canOperate(engine),
          isWorking: engine.isBusy || presentation.isPerforming,
          start: { Task.immediate { await presentation.start(engine) } },
          pause: { presentation.requestPause(engine) },
          resume: { presentation.requestResume(engine) },
          finish: { presentation.requestFinish(engine) })
      }
      .padding()
      .frame(maxWidth: .infinity)
      .background(.bar)
    }
  }

  /// Access problems matter only before a walk exists; afterwards the status banner reports them.
  private var accessNotice: IdleAccessNotice? {
    guard engine.phase == .idle, !engine.hasLiveSession else { return nil }
    return IdleAccessNotice(access: locationAccess, startFailure: engine.startFailure)
  }
}

private struct TrackingBanner: View {
  let engine: TrackingEngine
  let presentation: TrackingPresentation

  var body: some View {
    if let content = presentation.banner(for: engine) {
      StatusBanner(
        content: content, isWorking: engine.isBusy || presentation.isPerforming,
        retry: { Task.immediate { await presentation.retry(content, engine) } },
        dismiss: { engine.clearFailure() })
    }
  }
}

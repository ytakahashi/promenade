import Domain
import Foundation
import SwiftUI
import Tracking

public struct RootView: View {
  let engine: TrackingEngine
  let configuration: TrackingConfiguration
  let locationAccess: LocationAccessState
  let readSession: @MainActor (UUID) throws -> SessionRecord?
  /// Owned here rather than by the tab so presentation state outlives the tracking screen.
  @State private var trackingPresentation: TrackingPresentation

  public init(
    engine: TrackingEngine, configuration: TrackingConfiguration,
    locationAccess: LocationAccessState,
    readSession: @escaping @MainActor (UUID) throws -> SessionRecord?
  ) {
    self.engine = engine
    self.configuration = configuration
    self.locationAccess = locationAccess
    self.readSession = readSession
    _trackingPresentation = State(
      initialValue: TrackingPresentation(
        shortWalkPolicy: ShortWalkPolicy(configuration: configuration)))
  }

  public var body: some View {
    TabView {
      Tab {
        TrackingScreen(
          engine: engine, presentation: trackingPresentation, locationAccess: locationAccess)
      } label: {
        Label {
          Text("Tracking", bundle: .module)
        } icon: {
          Image(systemName: isRecording ? "record.circle.fill" : "figure.walk")
        }
      }
      .accessibilityValue(trackingAccessibilityValue)
      Tab {
        HistoryScreen()
      } label: {
        Label {
          Text("History", bundle: .module)
        } icon: {
          Image(systemName: "list.bullet")
        }
      }
      Tab {
        StatisticsScreen()
      } label: {
        Label {
          Text("Statistics", bundle: .module)
        } icon: {
          Image(systemName: "chart.bar")
        }
      }
    }
    // Attached above the tabs so launch recovery is decided whichever tab is shown.
    .recoveryAlert(
      trackingPresentation.recoveryDialog(for: engine),
      resume: { Task.immediate { await trackingPresentation.resolveRecovery(.resume, engine) } },
      finish: { Task.immediate { await trackingPresentation.resolveRecovery(.finish, engine) } }
    )
    .overlay(alignment: .top) {
      if let notice = engine.notice {
        AutoFinishToast(
          view: { trackingPresentation.showSummary(of: notice, engine) },
          dismiss: { engine.clearNotice() }
        )
        .padding()
        .transition(.move(edge: .top).combined(with: .opacity))
        .task(id: notice) {
          await trackingPresentation.presentNotice(engine) {
            try await Task.sleep(for: AutoFinishToast.displayDuration)
          }
        }
      }
    }
    .animation(.default, value: engine.notice)
    .onChange(of: engine.lastFinishedSessionID, initial: true) {
      trackingPresentation.consumeFinishedSession(engine)
    }
    .onChange(of: engine.isBusy) {
      trackingPresentation.consumeFinishedSession(engine)
    }
    .sheet(
      item: Binding(
        get: { trackingPresentation.summary },
        set: { if $0 == nil { trackingPresentation.dismissSummary() } })
    ) { item in
      SessionSummarySheet(
        model: SessionSummaryModel(
          sessionID: item.id, route: configuration.route, read: readSession),
        close: { trackingPresentation.dismissSummary() })
    }
  }

  private var isRecording: Bool {
    if case .recording = engine.phase { return true }
    return false
  }

  private var trackingAccessibilityValue: Text {
    switch engine.phase {
    case .recording: Text("Recording", bundle: .module)
    case .paused: Text("Paused", bundle: .module)
    default: Text("Not recording", bundle: .module)
    }
  }
}

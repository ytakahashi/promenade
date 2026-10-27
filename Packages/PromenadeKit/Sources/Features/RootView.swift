import Domain
import Foundation
import Persistence
import SwiftUI
import Tracking

public struct RootView: View {
  let engine: TrackingEngine
  let configuration: TrackingConfiguration
  let locationAccess: LocationAccessState
  let readSession: @MainActor (UUID) throws -> SessionRecord?
  /// Owned here rather than by the tab so presentation state outlives the tracking screen.
  @State private var trackingPresentation: TrackingPresentation
  /// Owned here so the loaded list and a pending deletion survive tab switches.
  @State private var historyModel: HistoryModel
  /// Keep the selected statistics period and metric across tab switches.
  @State private var statisticsModel: StatisticsModel
  @State private var settingsModel: SettingsModel

  public init(
    engine: TrackingEngine, configuration: TrackingConfiguration,
    locationAccess: LocationAccessState,
    readSession: @escaping @MainActor (UUID) throws -> SessionRecord?,
    listSessions: @escaping @MainActor () throws -> [SessionListItem],
    deleter: any SessionDeleting,
    motionAccess: @escaping @MainActor () -> MotionAccessState,
    infoDictionary: [String: Any]? = Bundle.main.infoDictionary
  ) {
    self.engine = engine
    self.configuration = configuration
    self.locationAccess = locationAccess
    self.readSession = readSession
    _trackingPresentation = State(
      initialValue: TrackingPresentation(
        shortWalkPolicy: ShortWalkPolicy(configuration: configuration)))
    _historyModel = State(initialValue: HistoryModel(list: listSessions, deleter: deleter))
    _statisticsModel = State(initialValue: StatisticsModel(list: listSessions))
    _settingsModel = State(
      initialValue: SettingsModel(infoDictionary: infoDictionary, motionAccess: motionAccess))
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
        HistoryScreen(
          model: historyModel, route: configuration.route, readSession: readSession,
          settings: settingsModel, locationAccess: locationAccess)
      } label: {
        Label {
          Text("History", bundle: .module)
        } icon: {
          Image(systemName: "list.bullet")
        }
      }
      Tab {
        StatisticsScreen(model: statisticsModel)
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

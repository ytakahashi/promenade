import Domain
import Foundation
import SwiftUI
import Tracking

public struct RootView: View {
  let engine: TrackingEngine
  let configuration: TrackingConfiguration
  let locationAccess: LocationAccessState
  let readSession: @MainActor (UUID) throws -> SessionRecord?

  public init(
    engine: TrackingEngine, configuration: TrackingConfiguration,
    locationAccess: LocationAccessState,
    readSession: @escaping @MainActor (UUID) throws -> SessionRecord?
  ) {
    self.engine = engine
    self.configuration = configuration
    self.locationAccess = locationAccess
    self.readSession = readSession
  }

  public var body: some View {
    TabView {
      Tab {
        TrackingScreen(engine: engine, locationAccess: locationAccess)
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

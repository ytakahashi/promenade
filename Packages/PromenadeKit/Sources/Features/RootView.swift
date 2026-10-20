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
        TrackingScreen()
      } label: {
        Label {
          Text("Tracking", bundle: .module)
        } icon: {
          Image(systemName: "figure.walk")
        }
      }
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
}

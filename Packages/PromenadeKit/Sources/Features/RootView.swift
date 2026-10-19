import SwiftUI

public struct RootView: View {
  public init() {}

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

#Preview {
  RootView()
}

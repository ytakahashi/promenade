import SwiftUI
import Tracking

struct TrackingScreen: View {
  let engine: TrackingEngine
  let locationAccess: LocationAccessState
  @State private var metricsHeight: CGFloat = 0

  var body: some View {
    GeometryReader { geometry in
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
            height: min(
              metricsHeight > 0 ? metricsHeight : geometry.size.height * 0.6,
              geometry.size.height * 0.6))
        }
      }
    }
  }
}

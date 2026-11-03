import Domain
import MapKit
import SwiftUI

struct SessionTrimMapView: View {
  let content: SessionTrimMapContent
  @State private var position: MapCameraPosition

  init(content: SessionTrimMapContent) {
    self.content = content
    // Fit the original walk once. Selection changes must not reset a camera the user has moved.
    _position = State(initialValue: .rect(content.bounds))
  }

  var body: some View {
    Map(position: $position) {
      ForEach(content.removed.segments) { segment in
        MapPolyline(coordinates: segment.coordinates)
          .stroke(.gray.opacity(0.5), style: StrokeStyle(lineWidth: 5, dash: [6, 4]))
      }
      ForEach(content.kept.segments) { segment in
        MapPolyline(coordinates: segment.coordinates)
          .stroke(.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
      }
      if let start = content.start, start != content.endpoint {
        Marker(
          String(localized: "Start", bundle: .module), systemImage: "flag.fill",
          coordinate: CLLocationCoordinate2D(start)
        )
        .tint(.green)
      }
      Marker(
        String(localized: "New Finish", bundle: .module), systemImage: "flag.checkered",
        coordinate: CLLocationCoordinate2D(content.endpoint)
      )
      .tint(.red)
    }
    .mapControls {
      MapCompass()
      MapScaleView()
    }
    .accessibilityIdentifier("trim.map")
  }
}

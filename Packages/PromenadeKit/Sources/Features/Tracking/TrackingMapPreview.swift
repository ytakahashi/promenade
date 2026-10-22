#if DEBUG
  import Domain
  import Foundation
  import MapKit
  import SwiftUI
  import Tracking

  extension TrackingMapContent {
    static func preview(pointCount: Int = 40) -> TrackingMapContent {
      let origin = Date(timeIntervalSinceReferenceDate: 800_000_000)
      let segments = (0..<2).map { segment in
        SegmentRecord(
          index: segment, startDate: origin,
          points: (0..<pointCount).map { index in
            TrackPoint(
              timestamp: origin.addingTimeInterval(Double(index)),
              coordinate: Coordinate(
                latitude: 35.68 + Double(index) * 0.000015,
                longitude: 139.75 + Double(segment) * 0.01 + sin(Double(index) * 0.02) * 0.003),
              horizontalAccuracy: 1, altitude: 0, verticalAccuracy: -1, speed: -1,
              speedAccuracy: -1, course: -1)
          })
      }
      return TrackingMapContent(route: LiveRoute(segments: segments, filter: RouteFilter()))
    }
  }

  #Preview("One point per segment") {
    RouteMapView(
      content: .preview(pointCount: 1), camera: .followsUser(.denied),
      initialPosition: .region(
        MKCoordinateRegion(
          center: CLLocationCoordinate2D(latitude: 35.68, longitude: 139.75),
          span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))))
  }

  #Preview("Two hours, 7,200 accepted points") {
    RouteMapView(
      content: .preview(pointCount: 3600), camera: .fitsRoute)
  }
#endif

import CoreLocation
import Domain
import Tracking

struct TrackingMapContent {
  struct Segment: Identifiable {
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
  }

  let segments: [Segment]

  init(route: LiveRoute?) {
    self.init(segments: route?.segments ?? [])
  }

  /// One accumulator per recorded segment, in order, so positions stay stable as segments are
  /// appended.
  init(segments accumulators: [RouteFilter.Accumulator]) {
    segments = accumulators.enumerated().compactMap { index, segment in
      // Each polyline owns one segment. Joining points across pauses would invent route geometry.
      guard segment.acceptedPoints.count >= 2 else { return nil }
      return Segment(
        id: index,
        coordinates: segment.acceptedPoints.map {
          CLLocationCoordinate2D(
            latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        })
    }
  }
}

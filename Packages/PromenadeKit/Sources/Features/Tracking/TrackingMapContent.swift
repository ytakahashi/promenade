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
        coordinates: segment.acceptedPoints.map { CLLocationCoordinate2D($0.coordinate) })
    }
  }
}

/// The first and last accepted points of a saved route, marked on its map.
struct RouteEndpoints: Equatable {
  let start: Coordinate
  /// `nil` when the route has a single accepted point, which is marked only as the start.
  let end: Coordinate?

  /// `points` are the accepted points of every segment in order.
  init?(points: [TrackPoint]) {
    guard let first = points.first, let last = points.last else { return nil }
    start = first.coordinate
    end = points.count > 1 ? last.coordinate : nil
  }
}

extension CLLocationCoordinate2D {
  init(_ coordinate: Coordinate) {
    self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
  }
}

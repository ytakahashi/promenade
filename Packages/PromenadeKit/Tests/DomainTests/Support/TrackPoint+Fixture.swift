import Foundation

@testable import Domain

extension Coordinate {
  static let origin = Coordinate(latitude: 35.0, longitude: 139.0)

  /// Moves the coordinate due north. Along a meridian the haversine distance equals the arc length,
  /// so `GeoDistance` between the two coordinates is exactly `meters`.
  func movedNorth(by meters: Double) -> Coordinate {
    let degrees = meters / GeoDistance.earthRadius * 180 / .pi
    return Coordinate(latitude: latitude + degrees, longitude: longitude)
  }
}

extension Date {
  static let reference = Date(timeIntervalSinceReferenceDate: 800_000_000)
}

extension TrackPoint {
  /// A point `north` meters north of `Coordinate.origin`, `seconds` after `Date.reference`.
  static func fixture(
    seconds: TimeInterval = 0,
    north: Double = 0,
    accuracy: Double = 5
  ) -> TrackPoint {
    TrackPoint(
      timestamp: Date.reference.addingTimeInterval(seconds),
      coordinate: Coordinate.origin.movedNorth(by: north),
      horizontalAccuracy: accuracy,
      altitude: 0,
      verticalAccuracy: 5,
      speed: -1,
      speedAccuracy: -1,
      course: -1
    )
  }
}

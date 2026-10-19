import Foundation

public enum GeoDistance {
  /// Mean Earth radius (IUGG) in meters.
  static let earthRadius: Double = 6_371_008.8

  /// Great-circle distance in meters using the haversine formula.
  ///
  /// Treats the Earth as a sphere, so results differ from `CLLocation.distance(from:)` by up to
  /// about 0.5%. This is negligible for walking distances and keeps the module free of CoreLocation.
  public static func meters(from a: Coordinate, to b: Coordinate) -> Double {
    let lat1 = a.latitude * .pi / 180
    let lat2 = b.latitude * .pi / 180
    let dLat = lat2 - lat1
    let dLon = (b.longitude - a.longitude) * .pi / 180

    let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
    return 2 * earthRadius * asin(min(1, sqrt(h)))
  }
}

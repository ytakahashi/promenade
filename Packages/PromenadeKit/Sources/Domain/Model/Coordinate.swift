import Foundation

/// A geographic coordinate in degrees (WGS 84).
public struct Coordinate: Sendable, Hashable {
  public var latitude: Double
  public var longitude: Double

  public init(latitude: Double, longitude: Double) {
    self.latitude = latitude
    self.longitude = longitude
  }
}

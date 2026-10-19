import Foundation

/// A single location fix. Mirrors the fields persisted for each recorded point.
public struct TrackPoint: Sendable, Hashable {
  public var timestamp: Date
  public var coordinate: Coordinate
  /// Radius of uncertainty in meters. Negative means the coordinate is invalid.
  public var horizontalAccuracy: Double
  /// Meters above sea level.
  public var altitude: Double
  /// Negative means the altitude is invalid.
  public var verticalAccuracy: Double
  /// Meters per second. Negative means invalid.
  public var speed: Double
  public var speedAccuracy: Double
  /// Degrees relative to true north. Negative means invalid.
  public var course: Double

  public init(
    timestamp: Date,
    coordinate: Coordinate,
    horizontalAccuracy: Double,
    altitude: Double,
    verticalAccuracy: Double,
    speed: Double,
    speedAccuracy: Double,
    course: Double
  ) {
    self.timestamp = timestamp
    self.coordinate = coordinate
    self.horizontalAccuracy = horizontalAccuracy
    self.altitude = altitude
    self.verticalAccuracy = verticalAccuracy
    self.speed = speed
    self.speedAccuracy = speedAccuracy
    self.course = course
  }
}

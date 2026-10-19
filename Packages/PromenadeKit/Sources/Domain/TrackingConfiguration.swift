import Foundation

/// Thresholds used while recording.
///
/// Kept as an injectable value instead of global constants so tests can override individual values.
public struct TrackingConfiguration: Sendable, Equatable {
  /// Maximum horizontal accuracy in meters for a point to be persisted as raw data.
  ///
  /// Points discarded here cannot be recovered later, so keep it lenient compared to `route`.
  public var storageMaxHorizontalAccuracy: Double
  /// Thresholds for distance and route drawing.
  public var route: RouteFilter.Configuration

  public init(storageMaxHorizontalAccuracy: Double, route: RouteFilter.Configuration) {
    self.storageMaxHorizontalAccuracy = storageMaxHorizontalAccuracy
    self.route = route
  }

  public static let `default` = TrackingConfiguration(
    storageMaxHorizontalAccuracy: 50,
    route: .default
  )
}

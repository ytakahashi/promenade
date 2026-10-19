import Foundation

/// Decides whether a received point is persisted as raw data.
///
/// Intentionally lenient compared to `RouteFilter` so that metrics can be recomputed later with
/// different route thresholds.
public struct StoragePointPolicy: Sendable {
  public var configuration: TrackingConfiguration

  public init(configuration: TrackingConfiguration = .default) {
    self.configuration = configuration
  }

  /// - Parameters:
  ///   - previous: The last point persisted in the current segment, if any.
  ///   - segmentStart: The start date of the current segment.
  public func accepts(_ point: TrackPoint, previous: TrackPoint?, segmentStart: Date) -> Bool {
    guard point.horizontalAccuracy >= 0,
      point.horizontalAccuracy <= configuration.storageMaxHorizontalAccuracy
    else { return false }
    if let previous, point.timestamp <= previous.timestamp { return false }
    return point.timestamp >= segmentStart
  }
}

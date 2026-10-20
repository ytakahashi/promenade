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
  /// Maximum gap in seconds before a nonstationary location update starts a new segment.
  public var signalGapThreshold: TimeInterval
  /// Maximum gap in seconds for continuing a segment after a background relaunch.
  public var relaunchSplitThreshold: TimeInterval
  /// Inactivity in seconds after which an unfinished session is automatically finished.
  public var autoFinishThreshold: TimeInterval
  /// Number of pending points that triggers a durable save.
  public var saveBatchSize: Int
  /// Seconds to wait for a definitive access result when resuming after a background relaunch
  /// before subscribing to location updates anyway.
  public var recoveryActivationTimeout: TimeInterval

  public init(
    storageMaxHorizontalAccuracy: Double,
    route: RouteFilter.Configuration,
    signalGapThreshold: TimeInterval = 60,
    relaunchSplitThreshold: TimeInterval = 60,
    autoFinishThreshold: TimeInterval = 6 * 60 * 60,
    saveBatchSize: Int = 10,
    recoveryActivationTimeout: TimeInterval = 10
  ) {
    self.storageMaxHorizontalAccuracy = storageMaxHorizontalAccuracy
    self.route = route
    self.signalGapThreshold = signalGapThreshold
    self.relaunchSplitThreshold = relaunchSplitThreshold
    self.autoFinishThreshold = autoFinishThreshold
    self.saveBatchSize = saveBatchSize
    self.recoveryActivationTimeout = recoveryActivationTimeout
  }

  public static let `default` = TrackingConfiguration(
    storageMaxHorizontalAccuracy: 50,
    route: .default
  )
}

import Foundation

/// Decides whether a walk being finished is short enough to offer discarding it.
public struct ShortWalkPolicy: Sendable {
  public var configuration: TrackingConfiguration

  public init(configuration: TrackingConfiguration = .default) {
    self.configuration = configuration
  }

  /// A walk exactly at either minimum is not short.
  public func isShort(distance: Double, walkingDuration: TimeInterval) -> Bool {
    distance < configuration.shortWalkMinimumDistance
      || walkingDuration < configuration.shortWalkMinimumDuration
  }
}

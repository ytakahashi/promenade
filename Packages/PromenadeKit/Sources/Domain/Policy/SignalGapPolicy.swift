import Foundation

/// Decides whether an incoming location should start a new segment.
public struct SignalGapPolicy: Sendable {
  public var configuration: TrackingConfiguration

  public init(configuration: TrackingConfiguration = .default) {
    self.configuration = configuration
  }

  public func shouldSplit(lastPointDate: Date?, point: TrackPoint, wasStationary: Bool) -> Bool {
    // The OS may stop delivering points while stationary; that silence is not a signal loss.
    guard !wasStationary, let lastPointDate else { return false }
    return point.timestamp.timeIntervalSince(lastPointDate) > configuration.signalGapThreshold
  }
}

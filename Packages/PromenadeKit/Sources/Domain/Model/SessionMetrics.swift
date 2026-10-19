import Foundation

/// Metrics derived from a session's recorded segments.
public struct SessionMetrics: Sendable, Equatable {
  /// Filtered route distance in meters.
  public var distance: Double
  public var timing: SessionTiming
  /// `nil` when any segment has unmeasured steps, or when there are no segments.
  public var steps: Int?

  public init(distance: Double, timing: SessionTiming, steps: Int?) {
    self.distance = distance
    self.timing = timing
    self.steps = steps
  }

  /// Meters per second, or `nil` when walking time is zero.
  public var averageSpeed: Double? {
    timing.walking > 0 ? distance / timing.walking : nil
  }

  /// Seconds per meter, or `nil` when distance or walking time is zero.
  ///
  /// A zero pace would read as infinitely fast, so it is treated as undefined as well.
  public var averagePace: Double? {
    distance > 0 && timing.walking > 0 ? timing.walking / distance : nil
  }
}

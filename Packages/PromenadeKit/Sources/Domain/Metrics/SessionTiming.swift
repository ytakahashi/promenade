import Foundation

/// Session time components, in seconds.
public struct SessionTiming: Sendable, Equatable {
  public var elapsed: TimeInterval
  public var walking: TimeInterval
  public var pause: TimeInterval
  public var interruption: TimeInterval

  public init(
    elapsed: TimeInterval,
    walking: TimeInterval,
    pause: TimeInterval,
    interruption: TimeInterval
  ) {
    self.elapsed = elapsed
    self.walking = walking
    self.pause = pause
    self.interruption = interruption
  }
}

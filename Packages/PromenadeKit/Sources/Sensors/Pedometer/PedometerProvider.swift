import Foundation

/// Authorization and availability of step counting.
public enum MotionAccess: Sendable, Equatable {
  case notDetermined
  case allowed
  case denied
  case restricted
  /// The device cannot count steps (e.g. the simulator).
  case unavailable
}

/// Step counting never throws: failing to count steps must not stop recording, so failures are
/// reported as unmeasured (`nil` or a stream without values).
///
/// Timeouts are applied by the caller so tests can control time.
public protocol PedometerProvider: Sendable {
  /// Current authorization and availability.
  var access: MotionAccess { get }
  /// Steps in the interval, or `nil` when unavailable, denied or failed.
  func steps(from start: Date, to end: Date) async -> Int?
  /// Cumulative steps since `start`. Finishes without values when unavailable or denied.
  /// Cancel the consuming task to stop updates.
  func liveSteps(from start: Date) -> AsyncStream<Int>
}

/// Step counting access as shown to the user. The app maps the sensor's state into this, so
/// Features does not depend on Sensors (as with `LocationAccessState`).
nonisolated public enum MotionAccessState: Sendable, Equatable {
  case notDetermined
  case allowed
  case denied
  case restricted
  /// The device cannot count steps.
  case unavailable
}

/// Why location access is unusable for recording. Only the user can resolve these in Settings.
///
/// Kept free of CoreLocation so features can explain each case without depending on sensors.
public enum LocationAccessIssue: Sendable, Equatable {
  /// Access was denied or restricted for the app.
  case denied
  /// Location Services are turned off for the whole device.
  case servicesDisabled
  /// Only approximate location is allowed.
  case accuracyLimited
}

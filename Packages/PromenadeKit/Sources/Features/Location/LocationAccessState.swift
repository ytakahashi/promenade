import CoreLocation

nonisolated public enum LocationAccessState: Sendable, Equatable {
  case notDetermined
  case available
  case denied
  case restricted
  case fullAccuracyRequired
  /// Location Services are off for the whole device; the app's own settings cannot fix this.
  case servicesDisabled
  case unavailable

  public static func resolve(
    authorization: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization,
    servicesEnabled: Bool = true
  ) -> Self {
    // Disabled services are also reported as `.denied`, so they must be checked first.
    guard servicesEnabled else { return .servicesDisabled }
    return switch authorization {
    // Accuracy has no meaning until authorization is decided.
    case .notDetermined: .notDetermined
    case .denied: .denied
    case .restricted: .restricted
    case .authorizedAlways, .authorizedWhenInUse:
      switch accuracy {
      case .fullAccuracy: .available
      case .reducedAccuracy: .fullAccuracyRequired
      @unknown default: .unavailable
      }
    @unknown default: .unavailable
    }
  }
}

import CoreLocation

nonisolated public enum LocationAccessState: Sendable, Equatable {
  case notDetermined
  case available
  case denied
  case restricted
  case fullAccuracyRequired
  case unavailable

  public static func resolve(
    authorization: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization
  ) -> Self {
    switch authorization {
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

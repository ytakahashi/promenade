import CoreLocation
import Observation

/// Read-only authorization state for idle UI. Authorization requests belong to LocationSession.
@MainActor
@Observable
public final class LocationAuthorizationMonitor: NSObject, @MainActor CLLocationManagerDelegate {
  public private(set) var authorizationStatus: CLAuthorizationStatus
  public private(set) var accuracyAuthorization: CLAccuracyAuthorization
  @ObservationIgnored private let manager: CLLocationManager

  public override init() {
    let manager = CLLocationManager()
    self.manager = manager
    authorizationStatus = manager.authorizationStatus
    accuracyAuthorization = manager.accuracyAuthorization
    super.init()
    // CLLocationManager delivers delegate callbacks on the run loop where it was created.
    manager.delegate = self
  }

  public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    authorizationStatus = manager.authorizationStatus
    accuracyAuthorization = manager.accuracyAuthorization
  }
}

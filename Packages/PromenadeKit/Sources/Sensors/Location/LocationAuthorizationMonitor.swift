import CoreLocation
import Observation

/// Read-only authorization state for idle UI. Authorization requests belong to LocationSession.
@MainActor
@Observable
public final class LocationAuthorizationMonitor: NSObject, @MainActor CLLocationManagerDelegate {
  public private(set) var authorizationStatus: CLAuthorizationStatus
  public private(set) var accuracyAuthorization: CLAccuracyAuthorization
  /// Assumed enabled until first checked, so an unchecked state never blocks Start; the engine
  /// still reports disabled services when recording begins.
  public private(set) var locationServicesEnabled = true
  @ObservationIgnored private let manager: CLLocationManager
  @ObservationIgnored private let readServicesEnabled: @Sendable () -> Bool

  public convenience override init() {
    self.init(readServicesEnabled: { CLLocationManager.locationServicesEnabled() })
  }

  init(readServicesEnabled: @escaping @Sendable () -> Bool) {
    let manager = CLLocationManager()
    self.manager = manager
    self.readServicesEnabled = readServicesEnabled
    authorizationStatus = manager.authorizationStatus
    accuracyAuthorization = manager.accuracyAuthorization
    super.init()
    // CLLocationManager delivers delegate callbacks on the run loop where it was created.
    manager.delegate = self
    Task { await refreshServicesEnabled() }
  }

  public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    refreshAuthorization()
    // Turning Location Services off is reported as `.denied`; read the global switch as well.
    Task { await refreshServicesEnabled() }
  }

  /// Rechecks per-app authorization on foreground entry without requesting access.
  public func refreshAuthorization() {
    authorizationStatus = manager.authorizationStatus
    accuracyAuthorization = manager.accuracyAuthorization
  }

  /// Rechecks whether Location Services are enabled for the device.
  ///
  /// `locationServicesEnabled()` can block and must not be called on the main thread, and it has
  /// no change notification, so callers refresh on foreground entry and authorization changes.
  public func refreshServicesEnabled() async {
    let read = readServicesEnabled
    locationServicesEnabled = await Task.detached { read() }.value
  }
}

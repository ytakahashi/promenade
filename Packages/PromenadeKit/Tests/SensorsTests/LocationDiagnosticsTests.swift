import CoreLocation
import Domain
import Foundation
import Testing

@testable import Sensors

struct LocationDiagnosticsTests {
  @Test func copiesEveryLocationFieldIncludingInvalidValues() {
    let location = CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: 35, longitude: 139), altitude: 42,
      horizontalAccuracy: -1, verticalAccuracy: -2, course: -3, courseAccuracy: -4,
      speed: -5, speedAccuracy: -6, timestamp: Date(timeIntervalSinceReferenceDate: 100))
    let point = TrackPoint(location: location)
    #expect(point.timestamp == location.timestamp)
    #expect(point.coordinate == Coordinate(latitude: 35, longitude: 139))
    #expect(point.altitude == 42)
    #expect(point.horizontalAccuracy == -1)
    #expect(point.verticalAccuracy == -2)
    #expect(point.course == -3)
    #expect(point.speed == -5)
    #expect(point.speedAccuracy == -6)
  }

  @Test func prioritizesAccessIssuesBeforeLocationAndStationarity() {
    var diagnostic = LocationDiagnostics(
      deniedGlobally: true, denied: true, restricted: true,
      insufficientlyInUse: true, accuracyLimited: true)
    #expect(
      diagnostic.event(point: point, stationary: true, unavailable: true)
        == .accessLost(.servicesDisabled))
    diagnostic.deniedGlobally = false
    #expect(diagnostic.issue == .denied)
    diagnostic.denied = false
    #expect(diagnostic.issue == .denied)
    diagnostic.restricted = false
    // Insufficient in-use status is not a user decision, so it is not an access issue.
    #expect(diagnostic.issue == .accuracyLimited)
    diagnostic.insufficientlyInUse = false
    #expect(diagnostic.issue == .accuracyLimited)
    diagnostic.accuracyLimited = false
    #expect(
      diagnostic.event(point: point, stationary: true, unavailable: true)
        == .location(point, stationary: true))
    #expect(diagnostic.event(point: nil, stationary: true, unavailable: true) == .stationary)
    #expect(diagnostic.event(point: nil, stationary: false, unavailable: true) == .unavailable)
    #expect(diagnostic.event(point: nil, stationary: false, unavailable: false) == nil)
  }

  @Test func waitsForDefinitiveAuthorizationAndRequiredSession() {
    var diagnostic = LocationDiagnostics(denied: true, requestInProgress: true)
    #expect(diagnostic.accessResult == nil)
    diagnostic.requestInProgress = false
    #expect(diagnostic.accessResult == .denied(.denied))
    diagnostic.denied = false
    diagnostic.serviceSessionRequired = true
    #expect(diagnostic.accessResult == nil)
    diagnostic.serviceSessionRequired = false
    #expect(diagnostic.accessResult == .granted)
  }

  @Test func insufficientInUseStatusIsTransientNotDenial() {
    let diagnostic = LocationDiagnostics(insufficientlyInUse: true)
    #expect(diagnostic.issue == nil)
    #expect(diagnostic.accessResult == nil)
    #expect(diagnostic.event(point: nil, stationary: false, unavailable: false) == .unavailable)
    #expect(
      diagnostic.event(point: point, stationary: false, unavailable: false)
        == .location(point, stationary: false))
  }

  @Test(arguments: [
    (CLAuthorizationStatus.authorizedWhenInUse, CLAccuracyAuthorization.fullAccuracy, true),
    (.authorizedAlways, .fullAccuracy, true),
    (.authorizedWhenInUse, .reducedAccuracy, false),
    (.notDetermined, .fullAccuracy, false),
    (.denied, .fullAccuracy, false),
    (.restricted, .fullAccuracy, false),
  ])
  func grantRequiresConfirmedPreciseAuthorization(
    _ authorization: CLAuthorizationStatus, _ accuracy: CLAccuracyAuthorization, _ granted: Bool
  ) {
    #expect(
      LocationDiagnostics().accessResult(authorization: authorization, accuracy: accuracy)
        == (granted ? .granted : nil))
  }

  @Test func reportedDenialDoesNotNeedConfirmation() {
    #expect(
      LocationDiagnostics(denied: true).accessResult(
        authorization: .authorizedWhenInUse, accuracy: .fullAccuracy) == .denied(.denied))
    #expect(
      LocationDiagnostics(requestInProgress: true).accessResult(
        authorization: .authorizedWhenInUse, accuracy: .fullAccuracy) == nil)
  }

  private var point: TrackPoint {
    TrackPoint(
      timestamp: Date(timeIntervalSinceReferenceDate: 100),
      coordinate: Coordinate(latitude: 35, longitude: 139), horizontalAccuracy: 5,
      altitude: 0, verticalAccuracy: -1, speed: -1, speedAccuracy: -1, course: -1)
  }
}

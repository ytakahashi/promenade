import CoreLocation
import Domain

/// A value snapshot keeps OS diagnostic objects out of event and authorization policy tests.
struct LocationDiagnostics: Sendable {
  var deniedGlobally = false
  var denied = false
  var restricted = false
  /// The app lacks in-use status (e.g. in the background without a background activity session).
  /// This is an app lifecycle condition, not a user decision, so it is never an access issue.
  var insufficientlyInUse = false
  var accuracyLimited = false
  var requestInProgress = false
  var serviceSessionRequired = false

  /// Access problems that only the user can resolve in Settings.
  var issue: LocationAccessIssue? {
    if deniedGlobally { return .servicesDisabled }
    if denied || restricted { return .denied }
    if accuracyLimited { return .accuracyLimited }
    return nil
  }

  var accessResult: LocationAccessResult? {
    // A pending permission dialog can temporarily report denial. Wait for its final result.
    guard !requestInProgress else { return nil }
    if let issue { return .denied(issue) }
    // Both are transient while resources are being set up; wait for a later diagnostic.
    guard !insufficientlyInUse, !serviceSessionRequired else { return nil }
    return .granted
  }

  /// `accessResult`, with a grant confirmed by the authorization state.
  ///
  /// Diagnostics report problems, so an all-clear value alone does not prove that authorization
  /// was decided. Keep waiting until the user actually granted precise when-in-use access.
  func accessResult(
    authorization: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization
  ) -> LocationAccessResult? {
    guard let result = accessResult else { return nil }
    guard result == .granted else { return result }
    switch authorization {
    case .authorizedWhenInUse, .authorizedAlways:
      return accuracy == .fullAccuracy ? .granted : nil
    default:
      return nil
    }
  }

  func event(point: TrackPoint?, stationary: Bool, unavailable: Bool) -> LocationEvent? {
    if let issue { return .accessLost(issue) }
    if let point { return .location(point, stationary: stationary) }
    if stationary { return .stationary }
    // Not receiving updates for lifecycle reasons is treated like a lost signal: the segment stays
    // open and a long silence is split as a signal gap.
    if unavailable || insufficientlyInUse { return .unavailable }
    return nil
  }
}

import CoreLocation
import Features
import Testing

struct LocationAccessStateTests {
  @Test(arguments: [CLAccuracyAuthorization.fullAccuracy, .reducedAccuracy])
  func undecidedAuthorizationIgnoresAccuracy(_ accuracy: CLAccuracyAuthorization) {
    #expect(
      LocationAccessState.resolve(authorization: .notDetermined, accuracy: accuracy)
        == .notDetermined)
    #expect(LocationAccessState.resolve(authorization: .denied, accuracy: accuracy) == .denied)
    #expect(
      LocationAccessState.resolve(authorization: .restricted, accuracy: accuracy) == .restricted)
  }

  @Test(arguments: [CLAuthorizationStatus.authorizedWhenInUse, .authorizedAlways])
  func authorizedAccessRequiresFullAccuracy(_ status: CLAuthorizationStatus) {
    #expect(
      LocationAccessState.resolve(authorization: status, accuracy: .fullAccuracy) == .available)
    #expect(
      LocationAccessState.resolve(authorization: status, accuracy: .reducedAccuracy)
        == .fullAccuracyRequired)
  }

  @Test(arguments: [
    CLAuthorizationStatus.notDetermined, .denied, .restricted, .authorizedWhenInUse,
  ])
  func disabledServicesTakePrecedence(_ status: CLAuthorizationStatus) {
    #expect(
      LocationAccessState.resolve(
        authorization: status, accuracy: .fullAccuracy, servicesEnabled: false)
        == .servicesDisabled)
  }

  @Test func unknownAuthorizationIsNotAvailable() throws {
    let status = try #require(CLAuthorizationStatus(rawValue: 999))
    #expect(
      LocationAccessState.resolve(authorization: status, accuracy: .fullAccuracy) == .unavailable)
  }
}

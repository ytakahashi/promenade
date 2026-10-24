import Foundation
import Testing

@testable import Features

@MainActor
struct SettingsModelTests {
  @Test func versionCombinesVersionAndBuild() {
    #expect(
      SettingsModel.version(infoDictionary: [
        "CFBundleShortVersionString": "1.0", "CFBundleVersion": "12",
      ]) == "1.0 (12)")
    #expect(SettingsModel.version(infoDictionary: ["CFBundleShortVersionString": "1.0"]) == "1.0")
    #expect(SettingsModel.version(infoDictionary: ["CFBundleVersion": "12"]) == "12")
    #expect(SettingsModel.version(infoDictionary: nil) == "--")
  }

  @Test func refreshReadsMotionAccessAgain() {
    let source = MotionSource()
    let model = SettingsModel(infoDictionary: nil, motionAccess: source.read)
    #expect(model.motion == .notDetermined)
    source.access = .allowed
    #expect(model.motion == .notDetermined)
    model.refresh()
    #expect(model.motion == .allowed)
  }

  @Test(arguments: [
    (LocationAccessState.available, PermissionStatus.allowed),
    (.fullAccuracyRequired, .preciseLocationOff),
    (.denied, .denied),
    (.restricted, .restricted),
    (.notDetermined, .notDetermined),
    (.servicesDisabled, .locationServicesOff),
    (.unavailable, .unavailable),
  ])
  func locationStatus(_ access: LocationAccessState, _ status: PermissionStatus) {
    #expect(PermissionStatus(access) == status)
  }

  @Test(arguments: [
    (MotionAccessState.allowed, PermissionStatus.allowed),
    (.denied, .denied),
    (.restricted, .restricted),
    (.notDetermined, .notDetermined),
    (.unavailable, .unavailable),
  ])
  func motionStatus(_ access: MotionAccessState, _ status: PermissionStatus) {
    #expect(PermissionStatus(access) == status)
  }
}

@MainActor
private final class MotionSource {
  var access = MotionAccessState.notDetermined
  func read() -> MotionAccessState { access }
}

import Foundation
import Testing

@testable import Domain

struct SignalGapPolicyTests {
  @Test(arguments: [-1.0, 0, 59, 60, 61])
  func splitsOnlyWhenGapExceedsThreshold(_ seconds: TimeInterval) {
    #expect(
      SignalGapPolicy().shouldSplit(
        lastPointDate: .reference, point: .fixture(seconds: seconds), wasStationary: false
      ) == (seconds > 60))
  }

  @Test func firstPointDoesNotSplit() {
    #expect(
      !SignalGapPolicy().shouldSplit(
        lastPointDate: nil, point: .fixture(seconds: 100), wasStationary: false))
  }

  @Test func stationarySilenceDoesNotSplit() {
    #expect(
      !SignalGapPolicy().shouldSplit(
        lastPointDate: .reference, point: .fixture(seconds: 100), wasStationary: true))
  }

  @Test func usesConfiguredThreshold() {
    var configuration = TrackingConfiguration.default
    configuration.signalGapThreshold = 10
    let policy = SignalGapPolicy(configuration: configuration)
    #expect(
      !policy.shouldSplit(
        lastPointDate: .reference, point: .fixture(seconds: 10), wasStationary: false))
    #expect(
      policy.shouldSplit(
        lastPointDate: .reference, point: .fixture(seconds: 11), wasStationary: false))
  }
}

import Foundation
import Testing

@testable import Domain

struct StoragePointPolicyTests {
  private let policy = StoragePointPolicy()

  @Test(arguments: [
    (accuracy: -1.0, accepted: false),
    (accuracy: 0.0, accepted: true),
    (accuracy: 50.0, accepted: true),
    (accuracy: 50.1, accepted: false),
  ])
  func horizontalAccuracy(accuracy: Double, accepted: Bool) {
    let point = TrackPoint.fixture(seconds: 1, accuracy: accuracy)
    #expect(policy.accepts(point, previous: nil, segmentStart: .reference) == accepted)
  }

  @Test(arguments: [
    (seconds: 9.0, accepted: false),
    (seconds: 10.0, accepted: false),
    (seconds: 11.0, accepted: true),
  ])
  func timestampMustAdvance(seconds: TimeInterval, accepted: Bool) {
    let previous = TrackPoint.fixture(seconds: 10)
    let point = TrackPoint.fixture(seconds: seconds)
    #expect(policy.accepts(point, previous: previous, segmentStart: .reference) == accepted)
  }

  @Test(arguments: [
    (seconds: -1.0, accepted: false),
    (seconds: 0.0, accepted: true),
  ])
  func timestampMustNotPrecedeSegmentStart(seconds: TimeInterval, accepted: Bool) {
    let point = TrackPoint.fixture(seconds: seconds)
    #expect(policy.accepts(point, previous: nil, segmentStart: .reference) == accepted)
  }

  @Test func usesConfiguredThreshold() {
    var configuration = TrackingConfiguration.default
    configuration.storageMaxHorizontalAccuracy = 10
    let policy = StoragePointPolicy(configuration: configuration)
    let point = TrackPoint.fixture(seconds: 1, accuracy: 20)
    #expect(!policy.accepts(point, previous: nil, segmentStart: .reference))
  }
}

import Foundation
import Testing

@testable import Domain

struct ShortWalkPolicyTests {
  @Test(arguments: [
    (49.9, 600.0, true),
    (500, 59.9, true),
    (10, 10, true),
    (50, 60, false),
    (500, 600, false),
  ])
  func isShortBelowEitherMinimum(distance: Double, walkingDuration: TimeInterval, short: Bool) {
    #expect(
      ShortWalkPolicy().isShort(distance: distance, walkingDuration: walkingDuration) == short)
  }

  @Test func usesConfiguredMinimums() {
    var configuration = TrackingConfiguration.default
    configuration.shortWalkMinimumDistance = 100
    configuration.shortWalkMinimumDuration = 120
    let policy = ShortWalkPolicy(configuration: configuration)
    #expect(policy.isShort(distance: 99, walkingDuration: 600))
    #expect(policy.isShort(distance: 500, walkingDuration: 119))
    #expect(!policy.isShort(distance: 100, walkingDuration: 120))
  }
}

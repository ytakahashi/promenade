import Foundation
import Testing

@testable import Domain

struct RouteFilterTests {
  private let filter = RouteFilter()

  @Test func rejectsPointsWithPoorOrInvalidAccuracy() {
    let result = filter.filter([
      .fixture(seconds: 0, accuracy: -1),
      .fixture(seconds: 1, accuracy: 20.1),
    ])
    #expect(result.acceptedPoints.isEmpty)
    #expect(result.distance == 0)
  }

  @Test func acceptsFirstPointWithoutDistance() {
    let point = TrackPoint.fixture(seconds: 0, accuracy: 20)
    let result = filter.filter([point])
    #expect(result.acceptedPoints == [point])
    #expect(result.distance == 0)
  }

  @Test func accumulatesDistanceWhileWalking() {
    let points: [TrackPoint] = [
      .fixture(seconds: 0, north: 0),
      .fixture(seconds: 10, north: 10),
      .fixture(seconds: 20, north: 20),
    ]
    let result = filter.filter(points)
    #expect(result.acceptedPoints == points)
    #expect(abs(result.distance - 20) < 1e-6)
  }

  @Test func ignoresJitterWithinAccuracyRadius() {
    let result = filter.filter([
      .fixture(seconds: 0, north: 0),
      .fixture(seconds: 1, north: 3),
      .fixture(seconds: 2, north: -2),
      .fixture(seconds: 3, north: 4.9),
    ])
    #expect(result.acceptedPoints.count == 1)
    #expect(result.distance == 0)
  }

  @Test(arguments: [
    (north: 4.9, accepted: false),
    (north: 5.1, accepted: true),
  ])
  func jitterRadiusBoundary(north: Double, accepted: Bool) {
    let result = filter.filter([
      .fixture(seconds: 0, north: 0, accuracy: 5),
      .fixture(seconds: 10, north: north, accuracy: 5),
    ])
    #expect(result.acceptedPoints.count == (accepted ? 2 : 1))
  }

  @Test func jitterRadiusUsesLargerAccuracy() {
    let result = filter.filter([
      .fixture(seconds: 0, north: 0, accuracy: 5),
      .fixture(seconds: 10, north: 8, accuracy: 10),
    ])
    #expect(result.acceptedPoints.count == 1)
  }

  @Test func rejectsPointsThatDoNotAdvanceInTime() {
    let result = filter.filter([
      .fixture(seconds: 10, north: 0),
      .fixture(seconds: 10, north: 20),
      .fixture(seconds: 5, north: 20),
    ])
    #expect(result.acceptedPoints.count == 1)
  }

  @Test func rejectsWarpedPoint() {
    let result = filter.filter([
      .fixture(seconds: 0, north: 0),
      .fixture(seconds: 10, north: 10),
      .fixture(seconds: 20, north: 500),  // 49 m/s
      .fixture(seconds: 30, north: 20),
    ])
    #expect(
      result.acceptedPoints.map(\.timestamp) == [0, 10, 30].map(Date.reference.addingTimeInterval))
    #expect(abs(result.distance - 20) < 1e-6)
  }

  @Test(arguments: [
    (north: 83.0, accepted: true),  // 8.3 m/s
    (north: 84.0, accepted: false),  // 8.4 m/s, above 30 km/h
  ])
  func maxSpeedBoundary(north: Double, accepted: Bool) {
    let result = filter.filter([
      .fixture(seconds: 0, north: 0),
      .fixture(seconds: 10, north: north),
    ])
    #expect(result.acceptedPoints.count == (accepted ? 2 : 1))
  }

  @Test func resetsIsolatedOutlierAnchorAfterConsecutiveSpeedRejections() {
    let result = filter.filter([
      .fixture(seconds: 0, north: 0),  // outlier anchor, the only point of its run
      .fixture(seconds: 10, north: 1000),
      .fixture(seconds: 20, north: 1010),
      .fixture(seconds: 30, north: 1020),  // third consistent rejection: becomes the new anchor
      .fixture(seconds: 40, north: 1030),
    ])
    // The isolated outlier is dropped so the route is not drawn through it.
    #expect(
      result.acceptedPoints.map(\.timestamp) == [30, 40].map(Date.reference.addingTimeInterval))
    // The jump to the new anchor is not counted.
    #expect(abs(result.distance - 10) < 1e-6)
  }

  @Test func resetKeepsPreviousRunWithMultiplePoints() {
    let result = filter.filter([
      .fixture(seconds: 0, north: 0),
      .fixture(seconds: 10, north: 10),
      .fixture(seconds: 20, north: 1000),
      .fixture(seconds: 30, north: 1010),
      .fixture(seconds: 40, north: 1020),  // third consistent rejection: becomes the new anchor
    ])
    #expect(
      result.acceptedPoints.map(\.timestamp) == [0, 10, 40].map(Date.reference.addingTimeInterval))
    #expect(abs(result.distance - 10) < 1e-6)
  }

  @Test func scatteredOutliersDoNotResetAnchor() {
    let result = filter.filter([
      .fixture(seconds: 0, north: 0),
      .fixture(seconds: 10, north: 10),
      // Three rejections in a row, but each is far from the previous one.
      .fixture(seconds: 11, north: 1000),
      .fixture(seconds: 12, north: -1000),
      .fixture(seconds: 13, north: 1000),
      .fixture(seconds: 20, north: 20),
    ])
    #expect(
      result.acceptedPoints.map(\.timestamp) == [0, 10, 20].map(Date.reference.addingTimeInterval))
    #expect(abs(result.distance - 20) < 1e-6)
  }

  @Test func acceptedPointClearsSpeedRejectionCount() {
    let result = filter.filter([
      .fixture(seconds: 0, north: 0),
      .fixture(seconds: 1, north: 1000),
      .fixture(seconds: 10, north: 10),
      .fixture(seconds: 11, north: 1000),
      .fixture(seconds: 12, north: 1000),
      .fixture(seconds: 20, north: 20),
    ])
    #expect(
      result.acceptedPoints.map(\.timestamp) == [0, 10, 20].map(Date.reference.addingTimeInterval))
    #expect(abs(result.distance - 20) < 1e-6)
  }

  @Test func otherRejectionsKeepSpeedRejectionCount() {
    let result = filter.filter([
      .fixture(seconds: 0, north: 0),
      .fixture(seconds: 1, north: 1000),
      .fixture(seconds: 2, north: 1000),
      .fixture(seconds: 3, north: 1, accuracy: 30),  // rejected by accuracy
      .fixture(seconds: 4, north: 2),  // rejected as jitter
      .fixture(seconds: 5, north: 1000),  // third consistent rejection
    ])
    #expect(result.acceptedPoints.map(\.timestamp) == [Date.reference.addingTimeInterval(5)])
    #expect(result.distance == 0)
  }

  @Test func usesConfiguredResetCount() {
    var configuration = RouteFilter.Configuration.default
    configuration.speedRejectionResetCount = 1
    let result = RouteFilter(configuration: configuration).filter([
      .fixture(seconds: 0, north: 0),
      .fixture(seconds: 1, north: 1000),
    ])
    #expect(result.acceptedPoints.map(\.timestamp) == [Date.reference.addingTimeInterval(1)])
    #expect(result.distance == 0)
  }

  @Test func batchMatchesIncrementalAdd() {
    let points: [TrackPoint] = [
      .fixture(seconds: 0, north: 0),
      .fixture(seconds: 5, north: 2),
      .fixture(seconds: 10, north: 12),
      .fixture(seconds: 11, north: 600),
      .fixture(seconds: 20, north: 25, accuracy: 40),
      .fixture(seconds: 30, north: 30),
      .fixture(seconds: 40, north: 45),
    ]
    var accumulator = filter.makeAccumulator()
    for point in points {
      accumulator.add(point)
    }
    let batch = filter.filter(points)
    #expect(accumulator.acceptedPoints == batch.acceptedPoints)
    #expect(accumulator.distance == batch.distance)
  }
}

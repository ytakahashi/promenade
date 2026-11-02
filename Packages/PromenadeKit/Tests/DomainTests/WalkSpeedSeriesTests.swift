import Foundation
import Testing

@testable import Domain

struct WalkSpeedSeriesTests {
  private func at(_ seconds: TimeInterval) -> Date {
    .reference.addingTimeInterval(seconds)
  }

  private func segment(
    index: Int = 0, start: TimeInterval, end: TimeInterval?,
    reason: SegmentEndReason = .finished, points: [TrackPoint] = []
  ) -> SegmentRecord {
    SegmentRecord(
      index: index, startDate: at(start), endDate: end.map(at), endReason: reason, points: points)
  }

  private func speeds(
    _ segments: [SegmentRecord], end: TimeInterval, interval: TimeInterval = 60
  ) -> [Double?] {
    let record = SessionRecord(
      id: UUID(), startDate: .reference, endDate: at(end), state: .finished,
      timeZoneIdentifier: "Asia/Tokyo", segments: segments)
    return WalkSpeedSeries.samples(for: record, filter: RouteFilter(), interval: interval)
      .map(\.speed)
  }

  private func expectSpeeds(
    _ actual: [Double?], _ expected: [Double?], sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(actual.count == expected.count, sourceLocation: sourceLocation)
    for (value, want) in zip(actual, expected) {
      switch (value, want) {
      case (let value?, let want?):
        #expect(abs(value - want) < 1e-6, "\(value) != \(want)", sourceLocation: sourceLocation)
      default:
        #expect(
          value == nil && want == nil, "\(actual) != \(expected)", sourceLocation: sourceLocation)
      }
    }
  }

  @Test func distanceGoesToTheIntervalOfThePointThatAddedIt() {
    let actual = speeds(
      [
        segment(
          start: 0, end: 120,
          points: [
            .fixture(seconds: 0),
            .fixture(seconds: 30, north: 30),
            .fixture(seconds: 90, north: 90),
          ])
      ], end: 120)
    expectSpeeds(actual, [0.5, 1])
  }

  @Test func samplesStartAtEachIntervalFromTheSessionStartThroughItsEnd() {
    let record = SessionRecord(
      id: UUID(), startDate: .reference, endDate: at(130), state: .finished,
      timeZoneIdentifier: "Asia/Tokyo",
      segments: [segment(start: 0, end: 130)])
    let samples = WalkSpeedSeries.samples(for: record, filter: RouteFilter(), interval: 60)
    #expect(samples.map(\.start) == [at(0), at(60), at(120)])
  }

  @Test(arguments: [SegmentEndReason.paused, .interrupted, .signalGap])
  func uncoveredIntervalsHaveNoSpeed(reason: SegmentEndReason) {
    let actual = speeds(
      [
        segment(
          index: 0, start: 0, end: 60, reason: reason,
          points: [.fixture(seconds: 0), .fixture(seconds: 30, north: 60)]),
        segment(
          index: 1, start: 180, end: 240,
          points: [.fixture(seconds: 180, north: 500), .fixture(seconds: 210, north: 530)]),
      ], end: 240)
    expectSpeeds(actual, [1, nil, nil, 0.5])
  }

  @Test func coveredIntervalWithoutPointsIsZero() {
    let actual = speeds(
      [
        segment(
          start: 0, end: 120, points: [.fixture(seconds: 0), .fixture(seconds: 30, north: 30)])
      ],
      end: 120)
    expectSpeeds(actual, [0.5, 0])
  }

  @Test func speedIsDividedByTheCoveredTimeOnly() {
    let actual = speeds(
      [
        segment(
          index: 0, start: 0, end: 30, reason: .paused,
          points: [.fixture(seconds: 0), .fixture(seconds: 30, north: 30)]),
        segment(
          index: 1, start: 50, end: 60,
          points: [.fixture(seconds: 50, north: 100), .fixture(seconds: 60, north: 110)]),
      ], end: 60)
    // 40 m over the 40 seconds both segments cover, not over the whole interval.
    expectSpeeds(actual, [1])
  }

  @Test func barelyCoveredIntervalWithDistanceDoesNotSpike() {
    let actual = speeds(
      [
        segment(
          start: 0, end: 61, reason: .paused,
          points: [
            .fixture(seconds: 0),
            .fixture(seconds: 50, north: 50),
            .fixture(seconds: 61, north: 70),
          ])
      ], end: 120)
    // 20 m with 1 second covered would read as 20 m/s.
    expectSpeeds(actual, [50.0 / 60, nil])
  }

  @Test func barelyCoveredIntervalWithoutDistanceDoesNotReadAsADrop() {
    let actual = speeds(
      [
        segment(
          index: 0, start: 0, end: 61, reason: .paused,
          points: [.fixture(seconds: 0), .fixture(seconds: 50, north: 50)]),
        segment(
          index: 1, start: 179, end: 240,
          points: [.fixture(seconds: 179, north: 500), .fixture(seconds: 230, north: 551)]),
      ], end: 240)
    expectSpeeds(actual, [50.0 / 60, nil, nil, 51.0 / 60])
  }

  @Test func barelyCoveredLastIntervalHasNoSpeed() {
    let actual = speeds(
      [
        segment(
          start: 0, end: 74, points: [.fixture(seconds: 0), .fixture(seconds: 30, north: 30)])
      ],
      end: 74)
    expectSpeeds(actual, [0.5, nil])
  }

  @Test func quarterOfAnIntervalIsEnoughForASpeed() {
    let actual = speeds(
      [
        segment(
          start: 0, end: 75, points: [.fixture(seconds: 0), .fixture(seconds: 70, north: 70)])
      ],
      end: 75)
    // 70 m in the second interval over its 15 covered seconds.
    expectSpeeds(actual, [0, 70.0 / 15])
  }

  @Test func coverageOfSeveralSegmentsInAnIntervalAddsUp() {
    let actual = speeds(
      [
        segment(
          index: 0, start: 0, end: 8, reason: .signalGap,
          points: [.fixture(seconds: 0), .fixture(seconds: 8, north: 8)]),
        segment(
          index: 1, start: 52, end: 60,
          points: [.fixture(seconds: 52, north: 100), .fixture(seconds: 60, north: 108)]),
      ], end: 60)
    expectSpeeds(actual, [1])
  }

  @Test func pointAtSegmentEndOnAnIntervalBoundaryStaysInTheCoveredInterval() {
    let actual = speeds(
      [
        segment(
          start: 0, end: 60, reason: .paused,
          points: [.fixture(seconds: 0), .fixture(seconds: 60, north: 60)])
      ], end: 120)
    expectSpeeds(actual, [1, nil])
  }

  @Test func pointAtSessionEndOnAnIntervalBoundaryIsInTheLastInterval() {
    let actual = speeds(
      [
        segment(
          start: 0, end: 60, points: [.fixture(seconds: 0), .fixture(seconds: 60, north: 60)])
      ],
      end: 60)
    expectSpeeds(actual, [1])
  }

  @Test func jitterWhileStationaryIsZero() {
    let actual = speeds(
      [
        segment(
          start: 0, end: 60,
          points: [
            .fixture(seconds: 0),
            .fixture(seconds: 20, north: 3),
            .fixture(seconds: 40, north: -3),
            .fixture(seconds: 60, north: 2),
          ])
      ], end: 60)
    expectSpeeds(actual, [0])
  }

  @Test func jumpOfAnAnchorResetIsNotCounted() {
    let actual = speeds(
      [
        segment(
          start: 0, end: 60,
          points: [
            .fixture(seconds: 0),
            .fixture(seconds: 10, north: 12),
            .fixture(seconds: 20, north: 1000),
            .fixture(seconds: 30, north: 1012),
            .fixture(seconds: 40, north: 1024),
            .fixture(seconds: 50, north: 1036),
          ])
      ], end: 60)
    // 12 m before the jump and 12 m after the new anchor.
    expectSpeeds(actual, [24.0 / 60])
  }

  @Test func segmentOfASingleInstantIsIgnored() {
    let actual = speeds(
      [
        segment(
          index: 0, start: 10, end: 10, reason: .signalGap, points: [.fixture(seconds: 10)]),
        segment(index: 1, start: 120, end: 180),
      ], end: 180)
    expectSpeeds(actual, [nil, nil, 0])
  }

  @Test func unfinishedOrZeroLengthSessionHasNoSamples() {
    let unfinished = SessionRecord(
      id: UUID(), startDate: .reference, state: .recording, timeZoneIdentifier: "Asia/Tokyo",
      segments: [segment(start: 0, end: nil, points: [.fixture(seconds: 0)])])
    #expect(WalkSpeedSeries.samples(for: unfinished, filter: RouteFilter(), interval: 60).isEmpty)
    #expect(speeds([], end: 0).isEmpty)
  }
}

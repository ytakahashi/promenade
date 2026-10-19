import Foundation
import Testing

@testable import Domain

struct SessionMetricsCalculatorTests {
  private func segment(
    index: Int = 0,
    start: TimeInterval = 0,
    end: TimeInterval? = nil,
    reason: SegmentEndReason? = nil,
    steps: Int? = nil,
    points: [TrackPoint] = []
  ) -> SegmentRecord {
    SegmentRecord(
      index: index,
      startDate: .reference.addingTimeInterval(start),
      endDate: end.map { Date.reference.addingTimeInterval($0) },
      endReason: reason,
      steps: steps,
      points: points
    )
  }

  private func session(
    segments: [SegmentRecord], end: TimeInterval? = nil
  ) -> SessionRecord {
    SessionRecord(
      id: UUID(),
      startDate: .reference,
      endDate: end.map { Date.reference.addingTimeInterval($0) },
      state: end == nil ? .recording : .finished,
      timeZoneIdentifier: "Asia/Tokyo",
      segments: segments
    )
  }

  private func timing(_ segments: [SegmentRecord], asOf: TimeInterval = 100) -> SessionTiming {
    SessionMetricsCalculator.timing(
      segments: segments,
      sessionStart: .reference,
      asOf: .reference.addingTimeInterval(asOf)
    )
  }

  private func metrics(_ session: SessionRecord, asOf: TimeInterval = 100) -> SessionMetrics {
    SessionMetricsCalculator.metrics(
      for: session, filter: RouteFilter(), asOf: .reference.addingTimeInterval(asOf))
  }

  @Test(arguments: [SegmentEndReason.paused, .interrupted, .signalGap, .finished])
  func classifiesGapByEndReason(_ reason: SegmentEndReason) {
    let result = timing([
      segment(end: 20, reason: reason),
      segment(index: 1, start: 50),
    ])
    #expect(result.elapsed == 100)
    #expect(result.pause == (reason == .paused ? 30 : 0))
    #expect(result.interruption == (reason == .interrupted ? 30 : 0))
    #expect(result.walking == 100 - result.pause - result.interruption)
  }

  @Test func combinesMultiplePausesAndInterruptionsWithoutExcludingSignalGaps() {
    let result = timing(
      [
        segment(end: 10, reason: .paused),
        segment(index: 1, start: 20, end: 30, reason: .interrupted),
        segment(index: 2, start: 50, end: 60, reason: .signalGap),
        segment(index: 3, start: 80, end: 90, reason: .paused),
      ], asOf: 120)
    #expect(result == SessionTiming(elapsed: 120, walking: 60, pause: 40, interruption: 20))
  }

  @Test func openSegmentWalksUntilAsOfWithoutPoints() {
    #expect(
      timing([segment()]) == SessionTiming(elapsed: 100, walking: 100, pause: 0, interruption: 0))
  }

  @Test(arguments: [SegmentEndReason.paused, .interrupted])
  func finalGapExtendsToCalculationEnd(_ reason: SegmentEndReason) {
    let result = timing([segment(end: 20, reason: reason)])
    #expect(result.walking == 20)
    #expect(result.pause == (reason == .paused ? 80 : 0))
    #expect(result.interruption == (reason == .interrupted ? 80 : 0))
  }

  @Test func pausedSessionUsesAsOfForOngoingRest() {
    var record = session(segments: [segment(end: 20, reason: .paused)])
    record.state = .paused
    #expect(
      metrics(record).timing == SessionTiming(elapsed: 100, walking: 20, pause: 80, interruption: 0)
    )
    #expect(metrics(record, asOf: 150).timing.pause == 130)
  }

  @Test func finishingWhilePausedIncludesFinalRestAndFreezesMetrics() {
    let record = session(segments: [segment(end: 20, reason: .paused)], end: 60)
    let result = metrics(record, asOf: 100)
    #expect(result.timing == SessionTiming(elapsed: 60, walking: 20, pause: 40, interruption: 0))
    #expect(metrics(record, asOf: 1000) == result)
    #expect(metrics(record, asOf: 10) == result)
  }

  @Test func clipsGapToAsOfEvenWhenLaterSegmentsExist() {
    let segments = [
      segment(end: 20, reason: .paused),
      segment(index: 1, start: 60, end: 80, reason: .interrupted),
    ]
    #expect(
      timing(segments, asOf: 40)
        == SessionTiming(elapsed: 40, walking: 20, pause: 20, interruption: 0))
    #expect(
      timing(segments, asOf: 10)
        == SessionTiming(elapsed: 10, walking: 10, pause: 0, interruption: 0))
    #expect(timing(segments, asOf: 20).pause == 0)
    #expect(timing(segments, asOf: 60).pause == 40)
  }

  @Test func clipsGapStartToSessionStart() {
    let result = timing([segment(start: -20, end: -10, reason: .interrupted)], asOf: 20)
    #expect(result == SessionTiming(elapsed: 20, walking: 0, pause: 0, interruption: 20))
  }

  @Test(arguments: [0.0, -10.0])
  func calculationEndAtOrBeforeStartHasZeroTime(_ asOf: TimeInterval) {
    let result = timing([segment(end: 20, reason: .paused)], asOf: asOf)
    #expect(result == SessionTiming(elapsed: 0, walking: 0, pause: 0, interruption: 0))
  }

  @Test func noSegmentsHasNoMeasuredDistanceOrSteps() {
    let result = metrics(session(segments: []))
    #expect(result.distance == 0)
    #expect(result.steps == nil)
    #expect(result.timing == SessionTiming(elapsed: 100, walking: 100, pause: 0, interruption: 0))
    #expect(result.averageSpeed == 0)
    #expect(result.averagePace == nil)
  }

  @Test func filtersEachSegmentIndependently() {
    let record = session(segments: [
      segment(
        end: 20, reason: .signalGap,
        points: [
          .fixture(seconds: 0),
          .fixture(seconds: 5, north: 2),  // Jitter is excluded.
          .fixture(seconds: 10, north: 10),
          .fixture(seconds: 11, north: 500),  // A speed outlier is excluded.
          .fixture(seconds: 20, north: 30, accuracy: 30),  // Poor accuracy is excluded.
        ]),
      segment(
        index: 1, start: 80,
        points: [
          .fixture(seconds: 80, north: 1000),
          .fixture(seconds: 90, north: 1020),
        ]),
    ])
    let result = metrics(record)
    #expect(abs(result.distance - 30) < 1e-6)
    #expect(result.timing.walking == 100)
    #expect(abs((result.averageSpeed ?? -1) - 0.3) < 1e-6)
    #expect(abs((result.averagePace ?? -1) - 100.0 / 30) < 1e-6)
  }

  @Test func usesInjectedRouteThresholds() {
    let record = session(segments: [
      segment(points: [
        .fixture(seconds: 0), .fixture(seconds: 10, north: 10),
      ])
    ])
    var configuration = RouteFilter.Configuration.default
    configuration.maxHorizontalAccuracy = 4
    let result = SessionMetricsCalculator.metrics(
      for: record,
      filter: RouteFilter(configuration: configuration),
      asOf: .reference.addingTimeInterval(100)
    )
    #expect(result.distance == 0)
  }

  @Test func sumsStepsOnlyWhenEverySegmentWasMeasured() {
    #expect(
      metrics(session(segments: [segment(steps: 10), segment(index: 1, steps: 20)])).steps == 30)
    #expect(metrics(session(segments: [segment(steps: 0)])).steps == 0)
    #expect(metrics(session(segments: [segment(steps: 10), segment(index: 1)])).steps == nil)
    #expect(metrics(session(segments: [segment()])).steps == nil)
  }

  @Test func averagesUseWalkingTimeInsteadOfElapsedTime() {
    let record = session(segments: [
      segment(
        end: 20, reason: .paused,
        points: [
          .fixture(seconds: 0), .fixture(seconds: 20, north: 20),
        ])
    ])
    let result = metrics(record)
    #expect(abs((result.averageSpeed ?? -1) - 1) < 1e-6)
    #expect(abs((result.averagePace ?? -1) - 1) < 1e-6)
  }

  @Test func averagesWithZeroWalkingTimeAreUndefined() {
    let timing = SessionTiming(elapsed: 0, walking: 0, pause: 0, interruption: 0)
    let zero = SessionMetrics(distance: 0, timing: timing, steps: nil)
    #expect(zero.averageSpeed == nil)
    #expect(zero.averagePace == nil)
    // A zero pace would read as infinitely fast, so it is undefined rather than 0.
    let distanceOnly = SessionMetrics(distance: 10, timing: timing, steps: nil)
    #expect(distanceOnly.averageSpeed == nil)
    #expect(distanceOnly.averagePace == nil)
  }
}

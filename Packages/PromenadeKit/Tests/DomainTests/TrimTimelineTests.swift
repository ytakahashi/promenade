import Foundation
import Testing

@testable import Domain

struct TrimTimelineTests {
  private func at(_ seconds: TimeInterval) -> Date {
    .reference.addingTimeInterval(seconds)
  }

  private func record(segments: [SegmentRecord], end: TimeInterval) -> SessionRecord {
    SessionRecord(
      id: UUID(),
      startDate: .reference,
      endDate: at(end),
      state: .finished,
      timeZoneIdentifier: "Asia/Tokyo",
      segments: segments
    )
  }

  @Test func datesAreEveryRecordedPointAcrossSegments() {
    let timeline = TrimTimeline(
      record: record(
        segments: [
          SegmentRecord(
            index: 0, startDate: at(0), endDate: at(20), endReason: .paused,
            // The inaccurate point is rejected by the filter but is still selectable.
            points: [.fixture(seconds: 0), .fixture(seconds: 10, accuracy: 40)]),
          SegmentRecord(
            index: 1, startDate: at(50), endDate: at(60), endReason: .finished,
            points: [.fixture(seconds: 50)]),
        ], end: 60),
      filter: RouteFilter())
    #expect(timeline.dates == [at(0), at(10), at(50)])
    #expect(timeline.distances.count == timeline.dates.count)
  }

  @Test func distanceRestartsAtEachSegmentWithoutCountingTheGap() {
    let timeline = TrimTimeline(
      record: record(
        segments: [
          SegmentRecord(
            index: 0, startDate: at(0), endDate: at(10), endReason: .paused,
            points: [.fixture(seconds: 0), .fixture(seconds: 10, north: 20)]),
          SegmentRecord(
            index: 1, startDate: at(100), endDate: at(110), endReason: .finished,
            points: [.fixture(seconds: 100, north: 500), .fixture(seconds: 110, north: 530)]),
        ], end: 110),
      filter: RouteFilter())
    let expected = [0, 20, 20, 50.0]
    #expect(timeline.distances.count == expected.count)
    #expect(zip(timeline.distances, expected).allSatisfy { abs($0 - $1) < 1e-6 })
  }

  @Test func pointsSharingATimeBecomeOneCandidate() {
    let timeline = TrimTimeline(
      record: record(
        segments: [
          SegmentRecord(
            index: 0, startDate: at(0), endDate: at(10), endReason: .interrupted,
            points: [.fixture(seconds: 0), .fixture(seconds: 10, north: 20)]),
          SegmentRecord(
            index: 1, startDate: at(10), endDate: at(20), endReason: .finished,
            points: [.fixture(seconds: 10, north: 20), .fixture(seconds: 20, north: 50)]),
        ], end: 20),
      filter: RouteFilter())
    #expect(timeline.dates == [at(0), at(10), at(20)])
    #expect(abs(timeline.distances[1] - 20) < 1e-6)
    #expect(abs(timeline.distances[2] - 50) < 1e-6)
  }

  @Test func candidateIsTheLatestPointAtOrBeforeTheDate() {
    let timeline = TrimTimeline(
      record: record(
        segments: [
          SegmentRecord(
            index: 0, startDate: at(0), endDate: at(20), endReason: .paused,
            points: [.fixture(seconds: 5), .fixture(seconds: 15)]),
          SegmentRecord(
            index: 1, startDate: at(100), endDate: at(110), endReason: .finished,
            points: [.fixture(seconds: 105)]),
        ], end: 110),
      filter: RouteFilter())
    #expect(timeline.candidate(atOrBefore: at(4)) == nil)
    #expect(timeline.candidate(atOrBefore: at(5)) == 0)
    #expect(timeline.candidate(atOrBefore: at(14)) == 0)
    #expect(timeline.candidate(atOrBefore: at(15)) == 1)
    // Inside the pause: snaps back to the point preceding the gap.
    #expect(timeline.candidate(atOrBefore: at(60)) == 1)
    #expect(timeline.candidate(atOrBefore: at(105)) == 2)
    #expect(timeline.candidate(atOrBefore: at(1000)) == 2)
  }

  @Test func sessionWithoutPointsHasNoCandidates() {
    let timeline = TrimTimeline(
      record: record(
        segments: [
          SegmentRecord(index: 0, startDate: at(0), endDate: at(10), endReason: .finished)
        ], end: 10),
      filter: RouteFilter())
    #expect(timeline.dates.isEmpty)
    #expect(timeline.candidate(atOrBefore: at(10)) == nil)
  }

  /// The preview reads the timeline and the store recomputes from the trimmed record; what the user
  /// sees before saving must be what is saved. Covers every candidate of a session with an anchor
  /// reset, a dropped first fix, a pause, an empty segment, a signal gap and segments sharing a
  /// point's time.
  @Test func everyCandidateMatchesMetricsOfTheTrimmedRecord() throws {
    let source = record(
      segments: [
        SegmentRecord(
          index: 0, startDate: at(0), endDate: at(60), endReason: .paused, steps: 50,
          points: [
            .fixture(seconds: 0),
            .fixture(seconds: 10, north: 2),  // Within the accuracy radius.
            .fixture(seconds: 20, north: 30),
            .fixture(seconds: 30, north: 2000),  // Consistent outliers that take over the anchor.
            .fixture(seconds: 40, north: 2030),
            .fixture(seconds: 50, north: 2060),
            .fixture(seconds: 60, north: 2090),
          ]),
        SegmentRecord(index: 1, startDate: at(90), endDate: at(90), endReason: .paused, steps: 0),
        SegmentRecord(
          index: 2, startDate: at(200), endDate: at(220), endReason: .signalGap, steps: 20,
          points: [
            .fixture(seconds: 200, north: 9000),  // A first fix that loses the anchor.
            .fixture(seconds: 210, north: 3000),
            .fixture(seconds: 215, north: 3010),
            .fixture(seconds: 220, north: 3020),
          ]),
        SegmentRecord(
          index: 3, startDate: at(400), endDate: at(430), endReason: .interrupted, steps: 30,
          points: [.fixture(seconds: 400, north: 3400), .fixture(seconds: 430, north: 3500)]),
        SegmentRecord(
          index: 4, startDate: at(430), endDate: at(450), endReason: .finished, steps: 15,
          points: [
            .fixture(seconds: 430, north: 3500),  // Same time as the previous segment's last point.
            .fixture(seconds: 450, north: 3530),
          ]),
      ], end: 450)
    let filter = RouteFilter()
    let timeline = TrimTimeline(record: source, filter: filter)
    #expect(timeline.dates.count == 14)

    for (date, distance) in zip(timeline.dates, timeline.distances) {
      let trimmed = try #require(source.trimmed(endingAt: date))
      let metrics = SessionMetricsCalculator.metrics(for: trimmed, filter: filter, asOf: date)
      // Exact: both sides add the same values in the same order.
      #expect(metrics.distance == distance)
      #expect(
        metrics.timing
          == SessionMetricsCalculator.timing(
            segments: source.segments, sessionStart: source.startDate, asOf: date))
    }
  }
}

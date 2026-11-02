import Foundation
import Testing

@testable import Domain

struct SessionRecordTests {
  private func session(segments: [SegmentRecord]) -> SessionRecord {
    SessionRecord(
      id: UUID(),
      startDate: .reference,
      state: .recording,
      timeZoneIdentifier: "Asia/Tokyo",
      segments: segments
    )
  }

  @Test func unmeasuredSegmentsAreClosedOnesWithoutStepsCoveringSignalGaps() {
    let at = { (seconds: TimeInterval) in Date.reference.addingTimeInterval(seconds) }
    let record = session(segments: [
      SegmentRecord(index: 0, startDate: at(0), endDate: at(10), endReason: .signalGap),
      SegmentRecord(index: 1, startDate: at(100), endDate: at(110), endReason: .paused),
      SegmentRecord(index: 2, startDate: at(200), endDate: at(210), endReason: .paused, steps: 5),
      SegmentRecord(index: 3, startDate: at(300)),
    ])
    let unmeasured = record.unmeasuredSegments
    #expect(unmeasured.map(\.index) == [0, 1])
    #expect(unmeasured.map(\.start) == [at(0), at(100)])
    // The signal gap's steps run up to the next segment; a pause ends at the segment's end.
    #expect(unmeasured.map(\.end) == [at(100), at(110)])
  }

  @Test func lastActivityWithoutSegmentsIsStartDate() {
    #expect(session(segments: []).lastActivityDate == .reference)
  }

  @Test func lastActivityOfEmptyOpenSegmentIsSegmentStart() {
    let segment = SegmentRecord(index: 0, startDate: .reference.addingTimeInterval(5))
    #expect(session(segments: [segment]).lastActivityDate == .reference.addingTimeInterval(5))
  }

  @Test func lastActivityIsLastPointOfOpenSegment() {
    let segment = SegmentRecord(
      index: 0,
      startDate: .reference,
      points: [.fixture(seconds: 10), .fixture(seconds: 20)]
    )
    #expect(session(segments: [segment]).lastActivityDate == .reference.addingTimeInterval(20))
  }

  @Test func lastActivityIsEndDateOfClosedSegment() {
    let segment = SegmentRecord(
      index: 0,
      startDate: .reference,
      endDate: .reference.addingTimeInterval(30),
      endReason: .paused,
      points: [.fixture(seconds: 10)]
    )
    #expect(session(segments: [segment]).lastActivityDate == .reference.addingTimeInterval(30))
  }

  @Test func hasOpenSegmentReflectsOnlyLastSegment() {
    let closed = SegmentRecord(
      index: 0,
      startDate: .reference,
      endDate: .reference.addingTimeInterval(10),
      endReason: .signalGap
    )
    let open = SegmentRecord(index: 1, startDate: .reference.addingTimeInterval(20))
    #expect(!session(segments: []).hasOpenSegment)
    #expect(!session(segments: [closed]).hasOpenSegment)
    #expect(session(segments: [closed, open]).hasOpenSegment)
  }

  @Test func lastActivityUsesOnlyLastSegment() {
    let first = SegmentRecord(
      index: 0,
      startDate: .reference,
      endDate: .reference.addingTimeInterval(100),
      endReason: .paused,
      points: [.fixture(seconds: 90)]
    )
    let second = SegmentRecord(index: 1, startDate: .reference.addingTimeInterval(200))
    #expect(
      session(segments: [first, second]).lastActivityDate == .reference.addingTimeInterval(200))
  }
}

struct SessionRecordTrimmedTests {
  private func at(_ seconds: TimeInterval) -> Date {
    .reference.addingTimeInterval(seconds)
  }

  private func finished(segments: [SegmentRecord], end: TimeInterval) -> SessionRecord {
    SessionRecord(
      id: UUID(),
      startDate: .reference,
      endDate: at(end),
      state: .finished,
      timeZoneIdentifier: "Asia/Tokyo",
      segments: segments
    )
  }

  /// Three segments: a pause, a signal gap (closed at its last point), and the finish.
  private var threeSegments: SessionRecord {
    finished(
      segments: [
        SegmentRecord(
          index: 0, startDate: at(0), endDate: at(100), endReason: .paused, steps: 10,
          points: [.fixture(seconds: 10), .fixture(seconds: 90)]),
        SegmentRecord(
          index: 1, startDate: at(200), endDate: at(290), endReason: .signalGap, steps: 20,
          points: [.fixture(seconds: 200), .fixture(seconds: 290)]),
        SegmentRecord(
          index: 2, startDate: at(400), endDate: at(500), endReason: .finished, steps: 30,
          points: [.fixture(seconds: 400), .fixture(seconds: 490)]),
      ], end: 500)
  }

  @Test func cuttingInsideASegmentDropsLaterPointsAndItsSteps() throws {
    let record = finished(
      segments: [
        SegmentRecord(
          index: 0, startDate: at(0), endDate: at(100), endReason: .finished, steps: 10,
          points: [.fixture(seconds: 10), .fixture(seconds: 20), .fixture(seconds: 30)])
      ], end: 100)
    let trimmed = try #require(record.trimmed(endingAt: at(20)))
    #expect(trimmed.endDate == at(20))
    #expect(trimmed.state == .finished)
    let segment = try #require(trimmed.segments.first)
    #expect(segment.points.map(\.timestamp) == [at(10), at(20)])
    #expect(segment.endDate == at(20))
    #expect(segment.endReason == .finished)
    #expect(segment.steps == nil)
  }

  @Test func laterSegmentsAreRemovedAndEarlierOnesKept() throws {
    let trimmed = try #require(threeSegments.trimmed(endingAt: at(200)))
    #expect(trimmed.segments.map(\.index) == [0, 1])
    #expect(trimmed.segments[0] == threeSegments.segments[0])
    #expect(trimmed.segments[1].points.map(\.timestamp) == [at(200)])
  }

  @Test func cuttingBeforeTheSegmentEndReplacesThePauseReason() throws {
    let trimmed = try #require(threeSegments.trimmed(endingAt: at(90)))
    #expect(trimmed.segments.map(\.index) == [0])
    #expect(trimmed.segments[0].endReason == .finished)
    #expect(trimmed.segments[0].endDate == at(90))
    // The saved steps run up to the pause at 100.
    #expect(trimmed.segments[0].steps == nil)
  }

  @Test func cuttingExactlyAtASegmentEndKeepsItsSteps() throws {
    let record = finished(
      segments: [
        SegmentRecord(
          index: 0, startDate: at(0), endDate: at(100), endReason: .paused, steps: 10,
          points: [.fixture(seconds: 10), .fixture(seconds: 100)]),
        SegmentRecord(
          index: 1, startDate: at(200), endDate: at(300), endReason: .finished, steps: 20,
          points: [.fixture(seconds: 200)]),
      ], end: 300)
    let trimmed = try #require(record.trimmed(endingAt: at(100)))
    #expect(trimmed.segments.map(\.index) == [0])
    #expect(trimmed.segments[0].steps == 10)
    #expect(trimmed.segments[0].endReason == .finished)
  }

  @Test func cuttingAtTheLastPointBeforeASignalGapDropsItsSteps() throws {
    // The segment is not shortened, but its steps include the gap that is being cut away.
    let trimmed = try #require(threeSegments.trimmed(endingAt: at(290)))
    #expect(trimmed.segments.last?.endDate == at(290))
    #expect(trimmed.segments.last?.endReason == .finished)
    #expect(trimmed.segments.last?.steps == nil)
  }

  @Test func signalGapBeforeTheCutKeepsItsSteps() throws {
    let trimmed = try #require(threeSegments.trimmed(endingAt: at(400)))
    #expect(trimmed.segments[1] == threeSegments.segments[1])
    #expect(trimmed.segments[1].steps == 20)
  }

  @Test func cuttingBetweenTheLastPointAndTheSegmentEndKeepsThePoints() throws {
    let trimmed = try #require(threeSegments.trimmed(endingAt: at(95)))
    #expect(trimmed.segments[0].points.count == 2)
    #expect(trimmed.segments[0].endDate == at(95))
    #expect(trimmed.segments[0].steps == nil)
  }

  @Test func emptySegmentBeforeTheCutIsKeptAndAfterItIsRemoved() throws {
    // Access loss then a pause leaves an empty zero-length segment holding the interruption.
    let record = finished(
      segments: [
        SegmentRecord(
          index: 0, startDate: at(0), endDate: at(50), endReason: .interrupted, steps: 5,
          points: [.fixture(seconds: 50)]),
        SegmentRecord(index: 1, startDate: at(60), endDate: at(60), endReason: .paused, steps: 0),
        SegmentRecord(
          index: 2, startDate: at(100), endDate: at(150), endReason: .finished, steps: 7,
          points: [.fixture(seconds: 100)]),
      ], end: 150)
    #expect(record.trimmed(endingAt: at(100))?.segments.map(\.index) == [0, 1, 2])
    #expect(record.trimmed(endingAt: at(50))?.segments.map(\.index) == [0])
  }

  @Test func cuttingAtTheSessionEndChangesNothing() {
    let record = threeSegments
    #expect(record.trimmed(endingAt: at(500)) == record)
  }

  @Test func tailAfterTheLastSegmentIsRemoved() throws {
    // Finished while paused: the session ends after its last segment.
    let record = finished(
      segments: [
        SegmentRecord(
          index: 0, startDate: at(0), endDate: at(100), endReason: .paused, steps: 10,
          points: [.fixture(seconds: 100)])
      ], end: 300)
    let trimmed = try #require(record.trimmed(endingAt: at(100)))
    #expect(trimmed.endDate == at(100))
    #expect(trimmed.segments[0].endReason == .finished)
    #expect(trimmed.segments[0].steps == 10)
  }

  @Test func cuttingAtATimeTwoSegmentsShareKeepsTheLaterOne() throws {
    let record = finished(
      segments: [
        SegmentRecord(
          index: 0, startDate: at(0), endDate: at(100), endReason: .interrupted, steps: 10,
          points: [.fixture(seconds: 100)]),
        SegmentRecord(
          index: 1, startDate: at(100), endDate: at(200), endReason: .finished, steps: 20,
          points: [.fixture(seconds: 100), .fixture(seconds: 200)]),
      ], end: 200)
    let trimmed = try #require(record.trimmed(endingAt: at(100)))
    #expect(trimmed.segments.map(\.index) == [0, 1])
    #expect(trimmed.segments[0] == record.segments[0])
    #expect(trimmed.segments[1].points.count == 1)
    #expect(trimmed.segments[1].steps == nil)
  }

  @Test func datesInAGapAreRejected() {
    // Closing a segment inside a pause or a signal gap would make the gap walking time.
    #expect(threeSegments.trimmed(endingAt: at(150)) == nil)
    #expect(threeSegments.trimmed(endingAt: at(350)) == nil)
  }

  @Test func datesInASegmentBeforeItsFirstPointAreRejected() {
    let record = finished(
      segments: [
        SegmentRecord(
          index: 0, startDate: at(0), endDate: at(100), endReason: .paused, steps: 10,
          points: [.fixture(seconds: 90)]),
        SegmentRecord(
          index: 1, startDate: at(200), endDate: at(300), endReason: .finished, steps: 20,
          points: [.fixture(seconds: 210)]),
      ], end: 300)
    #expect(record.trimmed(endingAt: at(205)) == nil)
    #expect(record.trimmed(endingAt: at(210)) != nil)
  }

  @Test func datesInASegmentWithoutPointsAreRejected() {
    let record = finished(
      segments: [
        SegmentRecord(
          index: 0, startDate: at(0), endDate: at(100), endReason: .paused, steps: 10,
          points: [.fixture(seconds: 90)]),
        SegmentRecord(
          index: 1, startDate: at(200), endDate: at(300), endReason: .paused, steps: 20),
        SegmentRecord(
          index: 2, startDate: at(400), endDate: at(500), endReason: .finished, steps: 30,
          points: [.fixture(seconds: 400)]),
      ], end: 500)
    #expect(record.trimmed(endingAt: at(250)) == nil)
  }

  @Test func datesOutsideTheRecordedRangeAreRejected() {
    #expect(threeSegments.trimmed(endingAt: at(5)) == nil)
    #expect(threeSegments.trimmed(endingAt: at(501)) == nil)
  }

  @Test func unfinishedSessionIsRejected() {
    var record = threeSegments
    record.state = .paused
    #expect(record.trimmed(endingAt: at(90)) == nil)
  }

  @Test func sessionWithoutPointsIsRejected() {
    let record = finished(
      segments: [SegmentRecord(index: 0, startDate: at(0), endDate: at(10), endReason: .finished)],
      end: 10)
    #expect(record.trimmed(endingAt: at(5)) == nil)
  }
}

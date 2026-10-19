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

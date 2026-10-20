import Domain
import Testing

@testable import Tracking

@MainActor
struct LiveRouteTests {
  @Test func restoredRouteMatchesIncrementalRouteWithoutBridgingSegments() {
    let initial = SessionRecord(
      id: .init(), startDate: date(0), state: .recording,
      timeZoneIdentifier: "UTC", segments: [SegmentRecord(index: 0, startDate: date(0))])
    let live = LiveSession(record: initial, filter: RouteFilter())
    live.append(point(0))
    live.append(point(10, north: 0.0001))
    live.close(at: date(10), reason: .signalGap)
    live.open(at: date(100))
    live.append(point(100, north: 1))
    live.append(point(110, north: 1.0001))
    let restored = LiveSession(record: live.record, filter: RouteFilter())
    #expect(restored.route.distance > 20)
    #expect(restored.route.distance < 25)
    #expect(restored.route.distance == live.route.distance)
    #expect(
      restored.route.segments.map(\.acceptedPoints) == live.route.segments.map(\.acceptedPoints))
    #expect(restored.timing(asOf: date(120)).walking == 120)
  }

  @Test func pauseAfterInterruptionPreservesTheTwoKindsOfGap() {
    let record = SessionRecord(
      id: .init(), startDate: date(0), state: .recording,
      timeZoneIdentifier: "UTC",
      segments: [
        SegmentRecord(index: 0, startDate: date(0), endDate: date(1), endReason: .interrupted)
      ])
    let live = LiveSession(record: record, filter: RouteFilter())
    live.pause(at: date(10))
    let timing = live.timing(asOf: date(20))
    #expect(timing.walking == 1)
    #expect(timing.interruption == 9)
    #expect(timing.pause == 10)
  }
}

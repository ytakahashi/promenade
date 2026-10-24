import Domain
import Foundation
import Observation
import Synchronization
import Testing

@testable import Features
@testable import Tracking

@MainActor
struct TrackingMapContentTests {
  @Test func shortSegmentsAreExcludedWithoutJoiningTheirNeighbors() {
    let content = TrackingMapContent(
      route: LiveRoute(
        segments: [
          segment(0, points: []), segment(1, points: [point(0)]),
          segment(2, points: [point(0), point(1)]),
          segment(3, points: [point(100), point(101)]),
        ], filter: RouteFilter()))
    #expect(content.segments.map(\.id) == [2, 3])
    #expect(content.segments.map { $0.coordinates.count } == [2, 2])
    #expect(content.segments[0].coordinates.last?.latitude == point(1).coordinate.latitude)
    #expect(content.segments[1].coordinates.first?.latitude == point(100).coordinate.latitude)
    #expect(TrackingMapContent(route: nil).segments.isEmpty)
  }

  @Test func drawsOnlyAcceptedPoints() {
    var rejected = point(1)
    rejected.horizontalAccuracy = 100
    let content = TrackingMapContent(
      route: LiveRoute(
        segments: [segment(0, points: [point(0), rejected, point(2)])], filter: RouteFilter()))
    #expect(content.segments.first?.coordinates.count == 2)
    #expect(content.segments.first?.coordinates.last?.latitude == point(2).coordinate.latitude)
  }

  @Test func timingChangesDoNotInvalidateRouteObservation() {
    let session = LiveSession(
      record: SessionRecord(
        id: UUID(), startDate: .distantPast, state: .recording, timeZoneIdentifier: "UTC",
        segments: [segment(0, points: [point(0), point(1)])]), filter: RouteFilter())
    let invalidated = Mutex(false)
    withObservationTracking {
      _ = TrackingMapContent(route: session.route)
    } onChange: {
      invalidated.withLock { $0 = true }
    }
    session.pause(at: point(2).timestamp, steps: nil)
    #expect(!invalidated.withLock { $0 })
    session.open(at: point(3).timestamp)
    #expect(invalidated.withLock { $0 })
  }

  private func segment(_ index: Int, points: [TrackPoint]) -> SegmentRecord {
    SegmentRecord(index: index, startDate: point(0).timestamp, points: points)
  }

  private func point(_ index: Int) -> TrackPoint {
    TrackPoint(
      timestamp: Date(timeIntervalSinceReferenceDate: Double(index) * 10),
      coordinate: Coordinate(latitude: 35 + Double(index) * 0.0001, longitude: 139),
      horizontalAccuracy: 1, altitude: 0, verticalAccuracy: -1, speed: -1, speedAccuracy: -1,
      course: -1)
  }
}

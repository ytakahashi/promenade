import Domain
import Testing

@testable import Features

@MainActor
struct SessionTrimMapContentTests {
  @Test func retainedGeometryMatchesFilteringTheTrimmedRecordAtEveryCandidate() throws {
    let record = TrimFixtures.record()
    let data = try #require(SessionTrimData(record: record, route: .default))
    for date in data.timeline.dates {
      let map = SessionTrimMapContent(data: data, endingAt: date)
      let trimmed = try #require(record.trimmed(endingAt: date))
      let expected = TrackingMapContent(
        segments: trimmed.segments.map { RouteFilter().filter($0.points) })
      #expect(map.kept.segments.map(\.id) == expected.segments.map(\.id))
      #expect(coordinates(map.kept) == coordinates(expected))
    }
  }

  @Test func removedGeometryRetainsBoundaryWithoutJoiningAcrossPause() throws {
    let data = try #require(SessionTrimData(record: TrimFixtures.record(), route: .default))
    let map = SessionTrimMapContent(data: data, endingAt: TrimFixtures.date(0))
    #expect(map.kept.segments.isEmpty)
    #expect(map.removed.segments.map(\.id) == [0, 1])
    #expect(map.removed.segments.map { $0.coordinates.count } == [2, 3])
    #expect(map.endpoint == TrimFixtures.point(0).coordinate)
    let later = SessionTrimMapContent(data: data, endingAt: TrimFixtures.date(40))
    #expect(later.removed.segments.map(\.id) == [1])
    #expect(
      later.removed.segments[0].coordinates.first?.latitude
        == TrimFixtures.point(40, north: 40).coordinate.latitude)
  }

  @Test func prefixBeforeAnchorResetDoesNotUseTheFullyFilteredRoute() throws {
    var record = TrimFixtures.record()
    record.segments = [
      .init(
        index: 0, startDate: TrimFixtures.date(0), endDate: TrimFixtures.date(60),
        endReason: .finished,
        points: [
          TrimFixtures.point(0, north: 1000), TrimFixtures.point(10),
          TrimFixtures.point(20, north: 10), TrimFixtures.point(30, north: 20),
          TrimFixtures.point(40, north: 30),
        ])
    ]
    let data = try #require(SessionTrimData(record: record, route: .default))
    #expect(data.filtered[0].acceptedPoints.first?.timestamp == TrimFixtures.date(30))
    let map = SessionTrimMapContent(data: data, endingAt: TrimFixtures.date(20))
    #expect(map.kept.segments.isEmpty)
    #expect(map.start == TrimFixtures.point(0, north: 1000).coordinate)
    #expect(map.endpoint == TrimFixtures.point(0, north: 1000).coordinate)
  }

  @Test func rejectedEndLocationUsesTheSavedRoutesLastAcceptedPoint() throws {
    var record = TrimFixtures.record()
    record.segments = [
      .init(
        index: 0, startDate: TrimFixtures.date(0), endDate: TrimFixtures.date(60),
        endReason: .finished,
        points: [
          TrimFixtures.point(0), TrimFixtures.point(10, north: 10),
          TrimFixtures.point(20, north: 20),
          TrimFixtures.point(30, north: 500, accuracy: 100),
          TrimFixtures.point(40, north: 40),
        ])
    ]
    let date = TrimFixtures.date(30)
    let data = try #require(SessionTrimData(record: record, route: .default))
    let map = SessionTrimMapContent(data: data, endingAt: date)
    let trimmed = try #require(record.trimmed(endingAt: date))
    let summary = try #require(SessionSummary(record: trimmed, route: .default))
    #expect(map.endpoint == TrimFixtures.point(20, north: 20).coordinate)
    #expect(map.endpoint == summary.endpoints?.end)
  }

  @Test(arguments: [false, true])
  func rejectedLocationAfterPauseUsesThePreviousSegmentsLastAcceptedPoint(
    emptyIntermediateSegment: Bool
  ) throws {
    var record = TrimFixtures.record()
    record.segments[1].points = [
      TrimFixtures.point(30, north: 500, accuracy: 100),
      TrimFixtures.point(40, north: 40),
    ]
    if emptyIntermediateSegment {
      record.segments[1].index = 2
      record.segments.insert(
        .init(
          index: 1, startDate: TrimFixtures.date(20), endDate: TrimFixtures.date(25),
          endReason: .paused, steps: 0), at: 1)
    }
    let date = TrimFixtures.date(30)
    let data = try #require(SessionTrimData(record: record, route: .default))
    let map = SessionTrimMapContent(data: data, endingAt: date)
    let trimmed = try #require(record.trimmed(endingAt: date))
    let summary = try #require(SessionSummary(record: trimmed, route: .default))
    #expect(map.endpoint == TrimFixtures.point(10, north: 10).coordinate)
    #expect(map.endpoint == summary.endpoints?.end)
  }

  @Test func rejectedPointsRemainSelectableWithoutInventingRouteGeometry() throws {
    var record = TrimFixtures.record()
    record.segments = [
      .init(
        index: 0, startDate: TrimFixtures.date(0), endDate: TrimFixtures.date(60),
        endReason: .finished,
        points: [TrimFixtures.point(0, accuracy: 100), TrimFixtures.point(10, accuracy: 100)])
    ]
    let data = try #require(SessionTrimData(record: record, route: .default))
    let map = SessionTrimMapContent(data: data, endingAt: TrimFixtures.date(0))
    #expect(map.kept.segments.isEmpty)
    #expect(map.removed.segments.isEmpty)
    #expect(map.start == nil)
    #expect(map.endpoint == record.segments[0].points[0].coordinate)
  }

  private func coordinates(_ content: TrackingMapContent) -> [[Double]] {
    content.segments.map { $0.coordinates.flatMap { [$0.latitude, $0.longitude] } }
  }
}

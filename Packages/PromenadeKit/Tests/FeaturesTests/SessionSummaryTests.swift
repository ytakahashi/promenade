import Domain
import Foundation
import Testing

@testable import Features

@MainActor
struct SessionSummaryTests {
  private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

  // MARK: Summary values

  @Test func metricsUseTheSavedEndAndSeparateSegments() throws {
    let record = finished(segments: [
      segment(0, from: 0, to: 20, reason: .paused, points: walk(from: 0, count: 5)),
      segment(1, from: 50, to: 70, reason: .interrupted, points: walk(from: 50, count: 1)),
      segment(2, from: 100, to: 120, reason: .finished, points: walk(from: 100, count: 5)),
    ])
    let summary = try #require(SessionSummary(record: record, route: .default))
    #expect(summary.metrics.timing.walking == 60)
    #expect(summary.metrics.timing.pause == 30)
    #expect(summary.metrics.timing.interruption == 30)
    // The one-point segment is not drawn, and segments are never joined.
    #expect(summary.map.segments.map(\.id) == [0, 2])
    let perSegment = try #require(
      SessionSummary(record: finished(segments: [record.segments[0]]), route: .default))
    #expect(summary.metrics.distance == perSegment.metrics.distance * 2)
  }

  @Test func unfinishedRecordHasNoSummary() {
    var record = finished(segments: [])
    record.state = .recording
    record.endDate = nil
    #expect(SessionSummary(record: record, route: .default) == nil)
  }

  @Test func invalidTimeZoneFallsBackToTheDevice() throws {
    var record = finished(segments: [])
    record.timeZoneIdentifier = "Not/AZone"
    #expect(try #require(SessionSummary(record: record, route: .default)).timeZone == .current)
    record.timeZoneIdentifier = "America/New_York"
    #expect(
      try #require(SessionSummary(record: record, route: .default)).timeZone.identifier
        == "America/New_York")
  }

  @Test func endpointsMarkTheFirstAndLastAcceptedPointsAcrossSegments() throws {
    let first = walk(from: 0, count: 5)
    let last = walk(from: 100, count: 5)
    let record = finished(segments: [
      segment(0, from: 0, to: 20, reason: .paused, points: first),
      segment(1, from: 50, to: 70, reason: .interrupted, points: walk(from: 50, count: 1)),
      segment(2, from: 100, to: 120, reason: .finished, points: last),
    ])
    let endpoints = try #require(SessionSummary(record: record, route: .default)?.endpoints)
    #expect(endpoints.start == first[0].coordinate)
    #expect(endpoints.end == last[4].coordinate)
  }

  @Test func walkWithoutAcceptedPointsHasNoEndpoints() throws {
    let empty = finished(segments: [segment(0, from: 0, to: 20, reason: .finished, points: [])])
    #expect(try #require(SessionSummary(record: empty, route: .default)).endpoints == nil)
    let single = finished(segments: [
      segment(0, from: 0, to: 20, reason: .finished, points: walk(from: 0, count: 1))
    ])
    let endpoints = try #require(SessionSummary(record: single, route: .default)?.endpoints)
    #expect(endpoints.end == nil)
  }

  // MARK: Model

  @Test func modelLoadsTheSavedWalk() async {
    let record = finished(segments: [])
    let model = SessionSummaryModel(sessionID: record.id, route: .default, read: { _ in record })
    #expect(model.isLoading)
    await model.load()
    #expect(model.loadedID == record.id)
  }

  @Test func modelKeepsTheLoadedWalkDuringAReadAndThenReportsItDeleted() async {
    let record = finished(segments: [])
    let reads = HeldReads()
    let model = SessionSummaryModel(sessionID: record.id, route: .default, read: reads.read)
    let first = Task { await model.load() }
    await reads.waitForRead(count: 1)
    #expect(model.isLoading)
    reads.release(0, returning: record)
    await first.value
    #expect(model.loadedID == record.id)

    let second = Task { await model.load() }
    await reads.waitForRead(count: 2)
    #expect(model.loadedID == record.id)
    reads.release(1, returning: nil)
    await second.value
    #expect(model.failure == .missing)
  }

  @Test func modelShowsProgressWhenRetryingAFailure() async {
    let reads = HeldReads()
    let model = SessionSummaryModel(sessionID: UUID(), route: .default, read: reads.read)
    let first = Task { await model.load() }
    await reads.waitForRead(count: 1)
    reads.release(0, returning: nil)
    await first.value
    #expect(model.failure == .missing)

    let retry = Task { await model.load() }
    await reads.waitForRead(count: 2)
    #expect(model.isLoading)
    reads.release(1, returning: nil)
    await retry.value
  }

  @Test func modelIgnoresASlowerEarlierRead() async {
    let record = finished(segments: [])
    let reads = HeldReads()
    let model = SessionSummaryModel(sessionID: record.id, route: .default, read: reads.read)
    let earlier = Task { await model.load() }
    await reads.waitForRead(count: 1)
    let later = Task { await model.load() }
    await reads.waitForRead(count: 2)
    reads.release(1, returning: record)
    await later.value
    reads.release(0, returning: nil)
    await earlier.value
    #expect(model.loadedID == record.id)
  }

  @Test func modelIgnoresACancelledRead() async {
    let record = finished(segments: [])
    let reads = HeldReads()
    let model = SessionSummaryModel(sessionID: record.id, route: .default, read: reads.read)
    let load = Task { await model.load() }
    await reads.waitForRead(count: 1)
    load.cancel()
    reads.release(0, returning: record)
    await load.value
    #expect(model.isLoading)
  }

  @Test func modelReportsEachFailureAndRetriesTheSameWalk() async {
    let id = UUID()
    var reads: [UUID] = []
    var result: Result<SessionRecord?, any Error> = .success(nil)
    let model = SessionSummaryModel(
      sessionID: id, route: .default,
      read: {
        reads.append($0)
        return try result.get()
      })
    await model.load()
    #expect(model.failure == .missing)
    result = .failure(CocoaError(.fileReadUnknown))
    await model.load()
    #expect(model.failure == .readFailed)
    var unfinished = finished(segments: [])
    unfinished.state = .paused
    unfinished.endDate = nil
    result = .success(unfinished)
    await model.load()
    #expect(model.failure == .unfinished)
    #expect(reads == [id, id, id])
  }

  // MARK: Fixtures

  private func finished(segments: [SegmentRecord]) -> SessionRecord {
    SessionRecord(
      id: UUID(), startDate: start, endDate: start.addingTimeInterval(segments.isEmpty ? 0 : 120),
      state: .finished, timeZoneIdentifier: "Asia/Tokyo", segments: segments)
  }

  private func segment(
    _ index: Int, from: TimeInterval, to: TimeInterval, reason: SegmentEndReason,
    points: [TrackPoint]
  ) -> SegmentRecord {
    SegmentRecord(
      index: index, startDate: start.addingTimeInterval(from),
      endDate: start.addingTimeInterval(to), endReason: reason, points: points)
  }

  /// Points 7 m apart every 5 seconds: accepted by the default route filter.
  private func walk(from offset: TimeInterval, count: Int) -> [TrackPoint] {
    (0..<count).map { index in
      TrackPoint(
        timestamp: start.addingTimeInterval(offset + Double(index) * 5),
        coordinate: Coordinate(latitude: 35 + Double(index) * 0.000063, longitude: 139),
        horizontalAccuracy: 5, altitude: 0, verticalAccuracy: -1, speed: -1, speedAccuracy: -1,
        course: -1)
    }
  }
}

/// Holds each read until the test releases it, so tests control the order reads finish in.
@MainActor
private final class HeldReads {
  private var waiting: [CheckedContinuation<SessionRecord?, Never>?] = []

  func read(_ id: UUID) async -> SessionRecord? {
    await withCheckedContinuation { waiting.append($0) }
  }

  func waitForRead(count: Int) async {
    while waiting.count < count { await Task.yield() }
  }

  func release(_ index: Int, returning record: SessionRecord?) {
    waiting[index]?.resume(returning: record)
    waiting[index] = nil
  }
}

@MainActor
extension SessionSummaryModel {
  fileprivate var isLoading: Bool {
    if case .loading = state { return true }
    return false
  }

  fileprivate var loadedID: UUID? {
    if case .loaded(let summary) = state { return summary.id }
    return nil
  }

  fileprivate var failure: Failure? {
    if case .failed(let failure) = state { return failure }
    return nil
  }
}

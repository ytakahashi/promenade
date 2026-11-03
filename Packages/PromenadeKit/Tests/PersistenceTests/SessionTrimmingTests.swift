import Domain
import Foundation
import SwiftData
import Testing

@testable import Persistence

@MainActor
struct SessionTrimmingTests {
  @Test(arguments: [Optional(8), nil])
  func trimDeletesTailAndUpdatesMetrics(steps: Int?) async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let saves = SaveController()
    let store = SwiftDataTrackingStore(container: container, save: saves.save)
    let id = try await seed(store)
    let original = try Fixtures.record(id, in: container)
    var expected = try #require(original.trimmed(endingAt: Fixtures.date(15)))
    expected.segments[expected.segments.count - 1].steps = steps
    let count = saves.count
    try await store.trimEnd(sessionID: id, at: Fixtures.date(15), steps: steps)
    #expect(saves.count == count + 1)
    #expect(try Fixtures.record(id, in: container) == expected)
    #expect(try ModelContext(container).fetchCount(FetchDescriptor<Segment>()) == 3)
    #expect(try Fixtures.storedPointCount(in: container) == 3)
    let metrics = SessionMetricsCalculator.metrics(
      for: expected, filter: .init(), asOf: Fixtures.date(15))
    try Fixtures.read(id, in: container) {
      #expect($0.distance == metrics.distance)
      #expect($0.walkingDuration == metrics.timing.walking)
      #expect($0.pauseDuration == metrics.timing.pause)
      #expect($0.interruptionDuration == metrics.timing.interruption)
      #expect($0.steps == metrics.steps)
      #expect($0.derivedDataVersion == DerivedDataVersion.current)
    }
    // Read back and recompute from persisted raw data, independent of the preview value.
    let reloaded = try Fixtures.record(id, in: container)
    #expect(
      SessionMetricsCalculator.metrics(for: reloaded, filter: .init(), asOf: Fixtures.date(99))
        == metrics)
  }

  @Test func signalGapBoundaryReplacesStepsAndDeletesFollowingSegments() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    try await store.append(Fixtures.point(1), sessionID: id)
    try await store.splitSegment(
      sessionID: id, closingAt: Fixtures.date(1), reason: .signalGap,
      steps: 100, nextStart: Fixtures.date(100))
    try await store.append(Fixtures.point(101), sessionID: id)
    try await store.finish(sessionID: id, at: Fixtures.date(110), steps: 10)
    let trimmed = try #require(
      try Fixtures.record(id, in: container).trimmed(endingAt: Fixtures.date(1)))
    #expect(trimmed.segments.last?.steps == nil)
    try await store.trimEnd(sessionID: id, at: Fixtures.date(1), steps: 1)
    let saved = try Fixtures.record(id, in: container)
    #expect(saved.segments.count == 1)
    #expect(saved.segments[0].endReason == .finished)
    #expect(saved.segments[0].steps == 1)
    #expect(try Fixtures.storedPointCount(in: container) == 1)
  }

  @Test(arguments: [nil, Optional(0), Optional(99)])
  func retainedStepsTakePrecedenceAtPauseBoundary(steps: Int?) async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    let id = try await seed(store)
    let trimmed = try #require(
      try Fixtures.record(id, in: container).trimmed(endingAt: Fixtures.date(2)))
    #expect(trimmed.segments.last?.steps == 2)
    try await store.trimEnd(sessionID: id, at: Fixtures.date(2), steps: steps)
    #expect(try Fixtures.record(id, in: container) == trimmed)
    try Fixtures.read(id, in: container) { #expect($0.steps == 2) }
  }

  @Test func invalidRequestsDoNotChangeTheRecordOrSave() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let saves = SaveController()
    let store = SwiftDataTrackingStore(container: container, save: saves.save)
    let id = try await seed(store)
    let original = try Fixtures.record(id, in: container)
    let count = saves.count
    // Before the first point, in a pause, and beyond the session end.
    for second in [0.0, 5, 31] {
      await #expect(throws: PersistenceError.invalidDate) {
        try await store.trimEnd(sessionID: id, at: Fixtures.date(second), steps: nil)
      }
    }
    let missing = UUID()
    await #expect(throws: PersistenceError.sessionNotFound(missing)) {
      try await store.trimEnd(sessionID: missing, at: Fixtures.date(1), steps: nil)
    }
    #expect(saves.count == count)
    #expect(try Fixtures.record(id, in: container) == original)
  }

  @Test func finishedSessionWithoutPointsIsRejected() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    try await store.finish(sessionID: id, at: Fixtures.date(10), steps: 10)
    let original = try Fixtures.record(id, in: container)
    await #expect(throws: PersistenceError.invalidDate) {
      try await store.trimEnd(sessionID: id, at: Fixtures.date(5), steps: nil)
    }
    #expect(try Fixtures.record(id, in: container) == original)
  }

  @Test(arguments: [false, true])
  func unfinishedSessionIsRejected(paused: Bool) async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    try await store.append(Fixtures.point(1), sessionID: id)
    if paused { try await store.pause(sessionID: id, at: Fixtures.date(2), steps: 2) }
    let original = try #require(try await store.loadSession(id: id))
    await #expect(throws: PersistenceError.sessionNotFinished) {
      try await store.trimEnd(sessionID: id, at: Fixtures.date(1), steps: nil)
    }
    #expect(try await store.loadSession(id: id) == original)
  }

  @Test(arguments: [Optional(3), nil])
  func failedTrimRollsBackAndPreservesOtherSessionsPendingPoints(steps: Int?) async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let saves = SaveController()
    let store = SwiftDataTrackingStore(container: container, save: saves.save)
    let id = try await seed(store)
    let original = try Fixtures.record(id, in: container)
    let active = UUID()
    try await store.createSession(
      id: active, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    try await store.append(Fixtures.point(1), sessionID: active)
    saves.failNext()
    await #expect(throws: SaveController.Failure.injected) {
      try await store.trimEnd(sessionID: id, at: Fixtures.date(15), steps: steps)
    }
    #expect(try Fixtures.record(id, in: container) == original)
    let restored = try await store.loadSession(id: id)
    #expect(restored == original)
    try await store.append(Fixtures.point(2), sessionID: active)
    try await store.flush()
    #expect(try Fixtures.record(id, in: container) == original)
    #expect(
      try Fixtures.record(active, in: container).segments[0].points == [
        Fixtures.point(1), Fixtures.point(2),
      ])
    // Retrying after rollback succeeds and leaves the other walk intact.
    try await store.trimEnd(sessionID: id, at: Fixtures.date(15), steps: 8)
    #expect(try Fixtures.record(id, in: container).endDate == Fixtures.date(15))
    #expect(try Fixtures.record(active, in: container).segments[0].points.count == 2)
  }

  @Test func successfulTrimSavesOtherSessionsPendingPointsAndRecordingContinues() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    let id = try await seed(store)
    let active = UUID()
    try await store.createSession(
      id: active, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    try await store.append(Fixtures.point(1), sessionID: active)
    try await store.trimEnd(sessionID: id, at: Fixtures.date(15), steps: 8)
    #expect(try Fixtures.record(active, in: container).segments[0].points == [Fixtures.point(1)])
    try await store.append(Fixtures.point(2), sessionID: active)
    try await store.finish(sessionID: active, at: Fixtures.date(3), steps: 3)
    #expect(try Fixtures.record(active, in: container).segments[0].points.count == 2)
  }

  private func seed(_ store: SwiftDataTrackingStore) async throws -> UUID {
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    try await store.append(Fixtures.point(1), sessionID: id)
    try await store.append(Fixtures.point(2, north: 10), sessionID: id)
    try await store.pause(sessionID: id, at: Fixtures.date(2), steps: 2)
    try await store.resume(sessionID: id, at: Fixtures.date(10))
    // Preserve an empty intermediate segment when trimming the later one.
    try await store.interruptSegment(sessionID: id, at: Fixtures.date(11), steps: 0)
    try await store.openSegment(sessionID: id, at: Fixtures.date(12))
    try await store.append(Fixtures.point(15, north: 20), sessionID: id)
    try await store.append(Fixtures.point(18, north: 30), sessionID: id)
    try await store.pause(sessionID: id, at: Fixtures.date(20), steps: 8)
    try await store.resume(sessionID: id, at: Fixtures.date(25))
    try await store.append(Fixtures.point(26, north: 40), sessionID: id)
    try await store.finish(sessionID: id, at: Fixtures.date(30), steps: 5)
    return id
  }
}

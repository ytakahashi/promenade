import Domain
import Foundation
import SwiftData
import Testing

@testable import Persistence

@MainActor
struct DerivedDataRecomputingTests {
  @Test func recomputesAllMetricsAndRemovesSessionFromPendingList() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let id = try oldSession(in: container)
    #expect(try reader(container).sessionIDsNeedingRecompute() == [id])
    let store: any DerivedDataRecomputing = SwiftDataTrackingStore(container: container)
    #expect(try await store.recomputeDerivedData(sessionID: id))
    try Fixtures.read(id, in: container) {
      #expect(abs($0.distance - 60) < 0.001)
      #expect($0.walkingDuration == 60)
      #expect($0.pauseDuration == 20)
      #expect($0.interruptionDuration == 20)
      #expect($0.steps == 60)
      #expect($0.derivedDataVersion == DerivedDataVersion.current)
      #expect($0.endDate == Fixtures.date(100))
    }
    #expect(try reader(container).sessionIDsNeedingRecompute().isEmpty)
  }

  @Test(arguments: [DerivedDataVersion.current, DerivedDataVersion.current + 1])
  func skipsCurrentAndFutureVersions(version: Int) async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let id = try oldSession(in: container, version: version)
    let saves = SaveController()
    let store = SwiftDataTrackingStore(container: container, save: saves.save)
    #expect(try await !store.recomputeDerivedData(sessionID: id))
    #expect(saves.count == 0)
    try Fixtures.read(id, in: container) {
      #expect($0.distance == 999)
      #expect($0.derivedDataVersion == version)
    }
  }

  @Test func rejectsUnfinishedSessionsAndSkipsMissingSessions() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    #expect(try await !store.recomputeDerivedData(sessionID: UUID()))
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    await #expect(throws: PersistenceError.sessionNotFinished) {
      try await store.recomputeDerivedData(sessionID: id)
    }
    try await store.pause(sessionID: id, at: Fixtures.date(10), steps: nil)
    await #expect(throws: PersistenceError.sessionNotFinished) {
      try await store.recomputeDerivedData(sessionID: id)
    }
    #expect(try reader(container).sessionIDsNeedingRecompute().isEmpty)
  }

  @Test(arguments: [false, true])
  func recomputationPreservesAnotherSessionsPendingPoints(failSave: Bool) async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let old = try oldSession(in: container)
    let saves = SaveController()
    let store = SwiftDataTrackingStore(container: container, save: saves.save)
    let recording = UUID()
    try await store.createSession(
      id: recording, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    try await store.append(Fixtures.point(1), sessionID: recording)
    if failSave {
      saves.failNext()
      await #expect(throws: SaveController.Failure.injected) {
        try await store.recomputeDerivedData(sessionID: old)
      }
      try Fixtures.read(old, in: container) {
        #expect($0.distance == 999)
        #expect($0.walkingDuration == 999)
        #expect($0.pauseDuration == 999)
        #expect($0.interruptionDuration == 999)
        #expect($0.steps == 999)
        #expect($0.derivedDataVersion == 0)
      }
      #expect(try Fixtures.record(recording, in: container).segments[0].points.isEmpty)
      // A read triggers replay before retry; it must neither duplicate points nor commit metrics.
      #expect(try await store.loadSession(id: recording)?.segments[0].points == [Fixtures.point(1)])
    }
    #expect(try await store.recomputeDerivedData(sessionID: old))
    try await store.append(Fixtures.point(2), sessionID: recording)
    try await store.flush()
    #expect(
      try Fixtures.record(recording, in: container).segments[0].points
        == [Fixtures.point(1), Fixtures.point(2)])
    #expect(try await !store.recomputeDerivedData(sessionID: old))
  }

  @Test func readerFiltersAndOrdersByStartThenID() throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    _ = try oldSession(in: container, id: second)
    _ = try oldSession(in: container, id: first)
    let older = try oldSession(in: container, start: -1000)
    _ = try oldSession(in: container, version: DerivedDataVersion.current)
    _ = try oldSession(in: container, version: DerivedDataVersion.current + 1)
    #expect(try reader(container).sessionIDsNeedingRecompute() == [older, first, second])
  }

  @Test func missingEndDateIsRejectedWithoutSaving() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let id = try oldSession(in: container)
    let context = ModelContext(container)
    let session = try #require(context.fetch(FetchDescriptor<WalkingSession>()).first)
    session.endDate = nil
    try context.save()
    let store = SwiftDataTrackingStore(container: container)
    await #expect(throws: PersistenceError.invalidStructure) {
      try await store.recomputeDerivedData(sessionID: id)
    }
    try Fixtures.read(id, in: container) { #expect($0.derivedDataVersion == 0) }
  }

  @Test func unmeasuredSegmentClearsSavedSteps() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let id = try oldSession(in: container)
    let context = ModelContext(container)
    let segment = try #require(context.fetch(FetchDescriptor<Segment>()).first)
    segment.steps = nil
    try context.save()
    let store = SwiftDataTrackingStore(container: container)
    #expect(try await store.recomputeDerivedData(sessionID: id))
    try Fixtures.read(id, in: container) { #expect($0.steps == nil) }
  }

  private func reader(_ container: ModelContainer) -> SessionReader {
    SessionReader(context: ModelContext(container))
  }

  private func oldSession(
    in container: ModelContainer, id: UUID = UUID(), start: TimeInterval = 0, version: Int = 0
  ) throws -> UUID {
    let context = ModelContext(container)
    context.autosaveEnabled = false
    let session = WalkingSession(
      id: id, startDate: Fixtures.date(start), stateRaw: SessionState.finished.rawValue,
      timeZoneIdentifier: Fixtures.timeZone.identifier)
    session.endDate = Fixtures.date(start + 100)
    session.distance = 999
    session.walkingDuration = 999
    session.pauseDuration = 999
    session.interruptionDuration = 999
    session.steps = 999
    session.derivedDataVersion = version
    context.insert(session)
    for (index, reason) in [SegmentEndReason.paused, .interrupted, .finished].enumerated() {
      let offset = start + Double(index * 40)
      let segment = Segment(index: index, startDate: Fixtures.date(offset))
      segment.endDate = Fixtures.date(offset + 20)
      segment.endReasonRaw = reason.rawValue
      segment.steps = (index + 1) * 10
      context.insert(segment)
      session.segments.append(segment)
      for point in [Fixtures.point(offset + 1), Fixtures.point(offset + 10, north: 20)] {
        let model = LocationPoint(point: point)
        context.insert(model)
        segment.points.append(model)
      }
    }
    try context.save()
    return id
  }
}

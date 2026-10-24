import Domain
import Foundation
import SwiftData
import Testing

@testable import Persistence

// Serialize container construction across suites; concurrent Core Data model setup can crash.
@MainActor
struct SessionDeletionTests {
  @Test func deletingFinishedSessionCascadesAndKeepsOthers() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    let kept = try await finishedSession(in: store, start: 0)
    let deleted = try await finishedSession(in: store, start: 1000)
    try await store.deleteSession(id: deleted)
    let context = ModelContext(container)
    #expect(try context.fetch(FetchDescriptor<WalkingSession>()).map(\.id) == [kept])
    #expect(try context.fetchCount(FetchDescriptor<Segment>()) == 1)
    #expect(try Fixtures.storedPointCount(in: container) == 2)
  }

  @Test func deletingUnfinishedSessionIsRejected() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    let recording = UUID()
    try await store.createSession(
      id: recording, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    try await store.append(Fixtures.point(1), sessionID: recording)
    await #expect(throws: PersistenceError.sessionNotFinished) {
      try await store.deleteSession(id: recording)
    }
    try await store.pause(sessionID: recording, at: Fixtures.date(10), steps: nil)
    await #expect(throws: PersistenceError.sessionNotFinished) {
      try await store.deleteSession(id: recording)
    }
    #expect(try Fixtures.record(recording, in: container).segments[0].points.count == 1)
  }

  @Test func deletingMissingSessionSucceeds() async throws {
    let store = SwiftDataTrackingStore(container: try ModelContainerFactory.make(inMemory: true))
    try await store.deleteSession(id: UUID())
    try await store.discard(sessionID: UUID())
  }

  @Test(arguments: [false, true])
  func discardDeletesUnfinishedSessionWithUnsavedPoints(paused: Bool) async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    for second in 1...3 { try await store.append(Fixtures.point(Double(second)), sessionID: id) }
    if paused { try await store.pause(sessionID: id, at: Fixtures.date(10), steps: nil) }
    try await store.discard(sessionID: id)
    let context = ModelContext(container)
    #expect(try context.fetchCount(FetchDescriptor<WalkingSession>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<Segment>()) == 0)
    #expect(try Fixtures.storedPointCount(in: container) == 0)
    #expect(try await store.loadSession(id: id) == nil)
  }

  @Test func failedDiscardKeepsSessionAndPendingPoints() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let saves = SaveController()
    let store = SwiftDataTrackingStore(container: container, save: saves.save)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    try await store.append(Fixtures.point(1), sessionID: id)
    saves.failNext()
    await #expect(throws: SaveController.Failure.injected) {
      try await store.discard(sessionID: id)
    }
    // A cancelled discard continues recording without losing unsaved points.
    try await store.append(Fixtures.point(2), sessionID: id)
    try await store.flush()
    #expect(
      try Fixtures.record(id, in: container).segments[0].points == [
        Fixtures.point(1), Fixtures.point(2),
      ])
  }

  private func finishedSession(in store: SwiftDataTrackingStore, start: TimeInterval)
    async throws -> UUID
  {
    let id = UUID()
    try await store.createSession(
      id: id, startDate: Fixtures.date(start), timeZone: Fixtures.timeZone)
    try await store.append(Fixtures.point(start + 1), sessionID: id)
    try await store.append(Fixtures.point(start + 2, north: 10), sessionID: id)
    try await store.finish(sessionID: id, at: Fixtures.date(start + 10), steps: 15)
    return id
  }
}

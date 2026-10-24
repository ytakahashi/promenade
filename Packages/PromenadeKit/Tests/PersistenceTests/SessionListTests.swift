import Domain
import Foundation
import SwiftData
import Testing

@testable import Persistence

// Serialize container construction across suites; concurrent Core Data model setup can crash.
@MainActor
struct SessionListTests {
  @Test func listsOnlyFinishedSessionsNewestFirstWithSavedMetrics() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    let older = try await finishedSession(in: store, start: 0, steps: 15)
    let newer = try await finishedSession(in: store, start: 1000, steps: nil)
    try await store.createSession(
      id: UUID(), startDate: Fixtures.date(2000), timeZone: Fixtures.timeZone)
    let items = try SessionReader(context: ModelContext(container)).finishedSessions()
    #expect(items.map(\.id) == [newer, older])
    let item = try #require(items.last)
    #expect(item.startDate == Fixtures.start)
    #expect(item.timeZoneIdentifier == "Asia/Tokyo")
    #expect(abs(item.distance - 20) < 0.001)
    #expect(item.walkingDuration == 30)
    #expect(item.steps == 15)
    #expect(items.first?.steps == nil)
  }

  @Test func emptyStoreListsNothing() throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    #expect(try SessionReader(context: ModelContext(container)).finishedSessions().isEmpty)
  }

  private func finishedSession(
    in store: SwiftDataTrackingStore, start: TimeInterval, steps: Int?
  ) async throws -> UUID {
    let id = UUID()
    try await store.createSession(
      id: id, startDate: Fixtures.date(start), timeZone: Fixtures.timeZone)
    try await store.append(Fixtures.point(start + 1), sessionID: id)
    try await store.append(Fixtures.point(start + 10, north: 20), sessionID: id)
    try await store.finish(sessionID: id, at: Fixtures.date(start + 30), steps: steps)
    return id
  }
}
